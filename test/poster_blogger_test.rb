require_relative "test_helper"
require "config"
require "poster/blogger"

class PosterBloggerTest < Minitest::Test
  class FakeApi
    attr_reader :inserted
    def insert_post(title:, html:)
      @inserted = { title: title, html: html }
      { "id" => "777", "url" => "https://hs9587.blogspot.com/2026/07/x.html" }
    end
  end

  Job = Struct.new(:sns, :text, :title, :media_urls, :media_paths, keyword_init: true)

  def config(dry_run: false)
    SnsMultipost::Config.new(
      "dry_run" => dry_run,
      "blogger" => { "client_id" => "CID", "client_secret" => "CSEC",
                     "refresh_token" => "RT", "blog_id" => "42" })
  end

  def build(cfg = config, api: FakeApi.new)
    SnsMultipost::Poster::Blogger.new(cfg, api: api)
  end

  def job(text: "本文", title: "タイトル", media_urls: [])
    Job.new(sns: "blogger", text: text, title: title, media_urls: media_urls, media_paths: [])
  end

  def test_perform_inserts_title_and_html_returns_url
    api = FakeApi.new
    result = build(api: api).perform(job(text: "こんにちは", title: "あいさつ"))
    assert_equal "あいさつ", api.inserted[:title]
    assert_equal "<p>こんにちは</p>", api.inserted[:html]
    assert_equal "777", result[:id]
    assert_equal "https://hs9587.blogspot.com/2026/07/x.html", result[:url]
  end

  def test_html_paragraphs_and_linebreaks
    api = FakeApi.new
    build(api: api).perform(job(text: "1行目\n2行目\n\n次段落"))
    assert_equal "<p>1行目<br>\n2行目</p>\n<p>次段落</p>", api.inserted[:html]
  end

  def test_html_escapes_and_appends_images
    api = FakeApi.new
    build(api: api).perform(job(text: "a<b>&c",
                                media_urls: ["https://m.example/1.jpg", "https://m.example/2.jpg"]))
    assert_includes api.inserted[:html], "a&lt;b&gt;&amp;c"
    assert_includes api.inserted[:html], '<img src="https://m.example/1.jpg">'
    assert_includes api.inserted[:html], '<img src="https://m.example/2.jpg">'
  end

  def test_image_count_capped_at_blogger_limit
    api = FakeApi.new
    urls = (1..25).map { |i| "https://m.example/#{i}.jpg" }
    build(api: api).perform(job(media_urls: urls))
    assert_equal 20, api.inserted[:html].scan("<img ").size
  end

  def test_title_fallback_when_blank
    api = FakeApi.new
    build(api: api).perform(job(text: "タイトル無しの本文です", title: ""))
    refute_empty api.inserted[:title]
  end

  def test_dry_run_does_not_call_api
    api = FakeApi.new
    out = build(config(dry_run: true), api: api).post(job)
    assert out[:dry_run]
    assert_nil api.inserted
  end

  def test_registered_in_registry
    assert_equal SnsMultipost::Poster::Blogger, SnsMultipost::Poster::REGISTRY["blogger"]
  end
end
