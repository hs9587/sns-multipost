require_relative "test_helper"
require "config"
require "poster/tumblr"

class PosterTumblrTest < Minitest::Test
  class FakeApi
    attr_reader :posted
    def create_post(text, image_paths: [])
      @posted = { text: text, image_paths: image_paths }
      { "response" => { "id" => 555, "id_string" => "555" } }
    end
  end

  Job = Struct.new(:sns, :text, :title, :media_paths, keyword_init: true)
  SILENT = ->(_m) {}

  def config(dry_run: false, blog: "hs9587.tumblr.com")
    SnsMultipost::Config.new(
      "dry_run" => dry_run,
      "tumblr" => { "access_token" => "TOK", "blog_identifier" => blog })
  end

  def build(cfg = config, api: FakeApi.new)
    SnsMultipost::Poster::Tumblr.new(cfg, api: api, logger: SILENT)
  end

  def test_perform_posts_text_and_returns_url
    api = FakeApi.new
    poster = build(api: api)
    job = Job.new(sns: "tumblr", text: "やあ", title: nil, media_paths: [])
    result = poster.perform(job)
    assert_equal "やあ", api.posted[:text]
    assert_equal "https://hs9587.tumblr.com/post/555", result[:url]
    assert_equal "555", result[:id]
  end

  def test_url_when_blog_identifier_is_bare_name
    api = FakeApi.new
    poster = build(config(blog: "hs9587"), api: api)
    job = Job.new(sns: "tumblr", text: "x", title: nil, media_paths: [])
    result = poster.perform(job)
    assert_equal "https://hs9587.tumblr.com/post/555", result[:url]
  end

  def test_perform_filters_images_by_count
    Dir.mktmpdir do |dir|
      paths = (1..12).map { |i| p = File.join(dir, "#{i}.jpg"); File.binwrite(p, "x"); p }
      api = FakeApi.new
      poster = build(api: api)
      job = Job.new(sns: "tumblr", text: "写真", title: nil, media_paths: paths)
      poster.perform(job)
      # 枚数上限 10 に切り詰め（tumblr はサイズ上限なしなので全通し）
      assert_equal 10, api.posted[:image_paths].size
    end
  end

  def test_dry_run_does_not_call_api
    api = FakeApi.new
    poster = build(config(dry_run: true), api: api)
    job = Job.new(sns: "tumblr", text: "x", title: nil, media_paths: [])
    out = poster.post(job)
    assert out[:dry_run]
    assert_nil api.posted
  end

  def test_registered_in_registry
    assert_equal SnsMultipost::Poster::Tumblr, SnsMultipost::Poster::REGISTRY["tumblr"]
  end
end
