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
      target: nil, with_images: true)

    assert_equal %w[fedibird bluesky tumblr mixi mixi2], selected
    assert_equal %w[blogger threads jotter], skipped
  end

  def test_explicit_unsupported_image_target_raises
    error = assert_raises(ArgumentError) do
      SnsMultipost::ManualPost.select_targets(
        configured: %w[bluesky], target: "threads", with_images: true)
    end
    assert_match(/--imageを利用できる投稿先がありません/, error.message)
  end

  def test_text_post_keeps_all_requested_targets
    selected, skipped = SnsMultipost::ManualPost.select_targets(
      configured: %w[threads jotter], target: nil, with_images: false)

    assert_equal %w[threads jotter], selected
    assert_empty skipped
  end
end
