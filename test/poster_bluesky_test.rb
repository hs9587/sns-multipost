require_relative "test_helper"
require "config"
require "poster/bluesky"

class PosterBlueskyTest < Minitest::Test
  # BlueskyApi の代役。呼ばれた引数を記録し、固定レスポンスを返す
  class FakeApi
    attr_reader :uploaded, :posted
    def initialize = (@uploaded = []; @posted = nil)
    def upload_blob(path)
      @uploaded << path
      { "$type" => "blob", "ref" => { "$link" => "blob-#{File.basename(path)}" } }
    end
    def create_post(text, blobs:, created_at:)
      @posted = { text: text, blobs: blobs, created_at: created_at }
      { "uri" => "at://did:plc:me/app.bsky.feed.post/rkeyZ", "cid" => "c" }
    end
  end

  Job = Struct.new(:sns, :text, :title, :media_paths, keyword_init: true)

  SILENT = ->(_m) {} # テスト出力を汚さないための無音ロガー

  def config(dry_run: false)
    SnsMultipost::Config.new(
      "dry_run" => dry_run,
      "bluesky" => { "handle" => "me.bsky.social", "app_password" => "pw" })
  end

  def build(cfg = config, api: FakeApi.new)
    SnsMultipost::Poster::Bluesky.new(cfg, api: api, clock: -> { Time.at(0).utc }, logger: SILENT)
  end

  def test_perform_posts_text_and_returns_url
    api = FakeApi.new
    poster = build(api: api)
    job = Job.new(sns: "bluesky", text: "やあ", title: nil, media_paths: [])
    result = poster.perform(job)
    assert_equal "やあ", api.posted[:text]
    assert_equal "1970-01-01T00:00:00Z", api.posted[:created_at]
    assert_equal "https://bsky.app/profile/me.bsky.social/post/rkeyZ", result[:url]
  end

  def test_perform_truncates_over_limit_text
    api = FakeApi.new
    poster = build(api: api)
    job = Job.new(sns: "bluesky", text: "あ" * 400, title: nil, media_paths: [])
    poster.perform(job)
    assert_equal 300, api.posted[:text].grapheme_clusters.length
  end

  def test_perform_uploads_images_within_count_and_size
    Dir.mktmpdir do |dir|
      paths = (1..6).map do |i|
        p = File.join(dir, "#{i}.jpg")
        File.binwrite(p, "x" * (i == 1 ? 2_000_000 : 100)) # 1枚目だけ超過
        p
      end
      api = FakeApi.new
      poster = build(api: api)
      job = Job.new(sns: "bluesky", text: "写真", title: nil, media_paths: paths)
      poster.perform(job)
      # 枚数上限 4 に切り詰め → うち1枚目(2MB)はサイズ超過で除外 → 3枚アップロード
      assert_equal 3, api.uploaded.size
      assert_equal 3, api.posted[:blobs].size
    end
  end

  def test_dry_run_does_not_call_api
    api = FakeApi.new
    poster = build(config(dry_run: true), api: api)
    job = Job.new(sns: "bluesky", text: "x", title: nil, media_paths: [])
    out = poster.post(job)
    assert out[:dry_run]
    assert_nil api.posted
  end

  def test_registered_in_registry
    assert_equal SnsMultipost::Poster::Bluesky,
                 SnsMultipost::Poster::REGISTRY["bluesky"]
  end
end
