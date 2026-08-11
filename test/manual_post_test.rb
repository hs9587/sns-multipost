require_relative "test_helper"
require "manual_post"

class ManualPostTest < Minitest::Test
  def test_resolves_existing_images_to_absolute_paths
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "one.jpg"), "image")

      paths = SnsMultipost::ManualPost.resolve_image_paths(["one.jpg"], base_dir: dir)

      assert_equal [File.join(dir, "one.jpg")], paths
    end
  end

  def test_missing_image_raises
    error = assert_raises(ArgumentError) do
      SnsMultipost::ManualPost.resolve_image_paths(["missing.jpg"])
    end
    assert_match(/画像ファイルが見つかりません/, error.message)
  end

  def test_image_post_selects_only_five_local_image_targets
    selected, skipped = SnsMultipost::ManualPost.select_targets(
      configured: %w[fedibird bluesky tumblr blogger threads mixi mixi2 jotter],
      targets: [], mode: :local_images)

    assert_equal %w[fedibird bluesky tumblr mixi mixi2], selected
    assert_equal %w[blogger threads jotter], skipped
  end

  def test_explicit_unsupported_image_target_raises
    error = assert_raises(ArgumentError) do
      SnsMultipost::ManualPost.select_targets(
        configured: %w[bluesky], targets: %w[threads], mode: :local_images)
    end
    assert_match(/--imageを利用できる投稿先がありません/, error.message)
  end

  def test_text_post_keeps_all_requested_targets
    selected, skipped = SnsMultipost::ManualPost.select_targets(
      configured: %w[threads jotter], targets: [], mode: nil)

    assert_equal %w[threads jotter], selected
    assert_empty skipped
  end

  def test_repeated_targets_are_kept_once
    selected, skipped = SnsMultipost::ManualPost.select_targets(
      configured: [], targets: %w[threads blogger threads], mode: :fedibird_latest)

    assert_equal %w[threads blogger], selected
    assert_empty skipped
  end

  class FakeFedibird
    attr_reader :account_id, :limit

    def initialize(statuses)
      @statuses = statuses
    end

    def statuses(account_id:, limit:)
      @account_id = account_id
      @limit = limit
      @statuses
    end
  end

  def test_latest_fedibird_source_extracts_text_and_image_urls
    api = FakeFedibird.new([
      { "content" => "<p>朝ごはん<br>です</p>", "url" => "https://fedibird.example/1",
        "media_attachments" => [
          { "type" => "image", "url" => "https://media.example/1.jpg" },
          { "type" => "image", "url" => "https://media.example/2.jpg" },
          { "type" => "video", "url" => "https://media.example/movie.mp4" },
        ] },
    ])

    source = SnsMultipost::ManualPost.latest_fedibird_source(api: api, account_id: "42")

    assert_equal "42", api.account_id
    assert_equal 1, api.limit
    assert_equal "朝ごはん\nです", source[:text]
    assert_equal %w[https://media.example/1.jpg https://media.example/2.jpg], source[:media_urls]
    assert_equal "https://fedibird.example/1", source[:source_url]
  end

  def test_latest_fedibird_source_requires_an_image
    api = FakeFedibird.new([
      { "content" => "<p>本文</p>", "url" => "https://fedibird.example/2",
        "media_attachments" => [] },
    ])

    error = assert_raises(ArgumentError) do
      SnsMultipost::ManualPost.latest_fedibird_source(api: api, account_id: "42")
    end
    assert_match(/最新投稿に画像がありません/, error.message)
  end

  def test_latest_fedibird_source_requires_a_status
    api = FakeFedibird.new([])

    error = assert_raises(ArgumentError) do
      SnsMultipost::ManualPost.latest_fedibird_source(api: api, account_id: "42")
    end
    assert_match(/最新投稿を取得できません/, error.message)
  end
end
