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

  class FakeImageStore
    attr_reader :calls
    def initialize(urls = ["https://blogger.googleusercontent.com/x/s0/1.jpg"])
      @urls = urls
      @calls = []
    end

    def urls_for(media_paths:, media_urls:, failure_screenshot_path: nil)
      @calls << { paths: media_paths, urls: media_urls,
                  screenshot: failure_screenshot_path }
      @urls
    end
  end

  Job = Struct.new(:sns, :text, :title, :media_urls, :media_paths, :path, keyword_init: true)

  def config(dry_run: false)
    SnsMultipost::Config.new(
      "dry_run" => dry_run,
      "blogger" => { "client_id" => "CID", "client_secret" => "CSEC",
                     "refresh_token" => "RT", "blog_id" => "42" })
  end

  def build(cfg = config, api: FakeApi.new, image_store: nil)
    SnsMultipost::Poster::Blogger.new(cfg, api: api, image_store: image_store)
  end

  def job(text: "本文", title: "タイトル", media_urls: [], media_paths: [], path: nil)
    Job.new(sns: "blogger", text: text, title: title,
            media_urls: media_urls, media_paths: media_paths, path: path)
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

  def test_images_are_rehosted_before_building_html
    api = FakeApi.new
    store = FakeImageStore.new([
      "https://blogger.googleusercontent.com/x/s0/1.jpg",
      "https://blogger.googleusercontent.com/x/s0/2.jpg"
    ])
    build(api: api, image_store: store).perform(
      job(text: "a<b>&c", media_urls: ["https://m.example/1.jpg", "https://m.example/2.jpg"]))

    assert_includes api.inserted[:html], "a&lt;b&gt;&amp;c"
    assert_includes api.inserted[:html],
                    '<img src="https://blogger.googleusercontent.com/x/s0/1.jpg">'
    assert_includes api.inserted[:html],
                    '<img src="https://blogger.googleusercontent.com/x/s0/2.jpg">'
    assert_equal ["https://m.example/1.jpg", "https://m.example/2.jpg"],
                 store.calls.first[:urls]
  end

  def test_image_count_capped_at_blogger_limit
    api = FakeApi.new
    urls = (1..25).map { |i| "https://m.example/#{i}.jpg" }
    stored = (1..20).map { |i| "https://blogger.googleusercontent.com/x/s0/#{i}.jpg" }
    image_store = FakeImageStore.new(stored)

    build(api: api, image_store: image_store).perform(job(media_urls: urls))

    assert_equal 20, api.inserted[:html].scan("<img ").size
    assert_equal 20, image_store.calls.first[:urls].length
  end

  def test_local_image_path_is_sent_to_image_store
    api = FakeApi.new
    image_store = FakeImageStore.new
    build(api: api, image_store: image_store).perform(
      job(media_paths: ["C:/photo.png"], path: "C:/repo/queue/job.json"))

    assert_equal ["C:/photo.png"], image_store.calls.first[:paths]
    assert_equal "C:/repo/failed/job.png", image_store.calls.first[:screenshot]
    assert_includes api.inserted[:html], "blogger.googleusercontent.com"
  end

  def test_title_fallback_when_blank
    api = FakeApi.new
    build(api: api).perform(job(text: "タイトルなしの本文です", title: ""))
    refute_empty api.inserted[:title]
  end

  def test_dry_run_does_not_call_api_or_image_store
    api = FakeApi.new
    image_store = FakeImageStore.new
    out = build(config(dry_run: true), api: api, image_store: image_store).post(
      job(media_paths: ["C:/photo.png"]))
    assert out[:dry_run]
    assert_nil api.inserted
    assert_empty image_store.calls
  end

  def test_registered_in_registry
    assert_equal SnsMultipost::Poster::Blogger,
                 SnsMultipost::Poster::REGISTRY["blogger"]
  end
end
