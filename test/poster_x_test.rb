require_relative "test_helper"
require "config"
require "poster/x"

class PosterXTest < Minitest::Test
  class FakeApi
    attr_reader :uploaded, :tweeted
    def initialize = (@uploaded = [])
    def upload_media(path)
      @uploaded << path
      "media-#{File.basename(path)}"
    end
    def create_tweet(text, media_ids: [])
      @tweeted = { text: text, media_ids: media_ids }
      { "data" => { "id" => "888", "text" => text } }
    end
  end

  Job = Struct.new(:sns, :text, :title, :media_paths, :media_urls, keyword_init: true)
  SILENT = ->(_m) {}

  def config(dry_run: false, username: "hs9587")
    SnsMultipost::Config.new(
      "dry_run" => dry_run,
      "x" => { "consumer_key" => "ck", "consumer_secret" => "cs",
               "access_token" => "at", "access_token_secret" => "ats",
               "username" => username })
  end

  def build(cfg = config, api: FakeApi.new)
    SnsMultipost::Poster::X.new(cfg, api: api, logger: SILENT)
  end

  def job(text: "やあ", media_paths: [])
    Job.new(sns: "x", text: text, title: nil, media_paths: media_paths, media_urls: [])
  end

  def test_perform_tweets_and_returns_url
    api = FakeApi.new
    result = build(api: api).perform(job(text: "やあ"))
    assert_equal "やあ", api.tweeted[:text]
    assert_equal "888", result[:id]
    assert_equal "https://x.com/hs9587/status/888", result[:url]
  end

  def test_truncates_over_limit_text
    api = FakeApi.new
    build(api: api).perform(job(text: "あ" * 400))
    assert_equal 280, api.tweeted[:text].grapheme_clusters.length
  end

  def test_uploads_images_within_count_and_size_then_attaches
    Dir.mktmpdir do |dir|
      paths = (1..6).map do |i|
        p = File.join(dir, "#{i}.jpg")
        File.binwrite(p, "x" * (i == 1 ? 6_000_000 : 100)) # 1枚目だけ 5MB 超
        p
      end
      api = FakeApi.new
      build(api: api).perform(job(media_paths: paths))
      # 枚数上限 4 → うち1枚目(6MB)はサイズ超過で除外 → 3枚アップロード
      assert_equal 3, api.uploaded.size
      assert_equal 3, api.tweeted[:media_ids].size
    end
  end

  def test_dry_run_does_not_call_api
    api = FakeApi.new
    out = build(config(dry_run: true), api: api).post(job)
    assert out[:dry_run]
    assert_nil api.tweeted
  end

  def test_registered_in_registry
    assert_equal SnsMultipost::Poster::X, SnsMultipost::Poster::REGISTRY["x"]
  end
end
