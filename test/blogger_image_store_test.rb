require_relative "test_helper"
require "blogger_image_store"

class BloggerImageStoreTest < Minitest::Test
  class MemoryStore
    attr_reader :saves
    def initialize(data = {}) = (@data, @saves = data, 0)
    def load = Marshal.load(Marshal.dump(@data))
    def save(data) = (@data = Marshal.load(Marshal.dump(data)); @saves += 1)
  end

  class FakeApi
    attr_reader :inserted, :deleted
    def initialize = (@inserted, @deleted, @next_id = [], [], 100)
    def insert_post(title:, html:, is_draft: false)
      @inserted << { title: title, html: html, is_draft: is_draft }
      @next_id += 1
      { "id" => @next_id.to_s }
    end
    def delete_post(id) = (@deleted << id; true)
  end

  class FakeBrowser
    attr_reader :calls
    def initialize = (@calls = [])
    def upload(draft_id:, media_paths:, failure_screenshot_path: nil)
      @calls << { draft_id: draft_id, paths: media_paths,
                  screenshot: failure_screenshot_path }
      media_paths.map.with_index do |path, index|
        url = "https://blogger.googleusercontent.com/img/x#{index}/s0/photo.png"
        yield(path, url) if block_given?
        url
      end
    end
  end

  def build(api:, browser:, store:, fetcher: ->(_url) { "remote-image" })
    SnsMultipost::BloggerImageStore.new(
      api: api, browser: browser, store: store, fetcher: fetcher,
      validator: ->(_url) { true })
  end

  def test_uploads_local_image_deletes_scratch_draft_and_caches_url
    Dir.mktmpdir do |dir|
      path = File.join(dir, "photo.png")
      File.binwrite(path, "image-bytes")
      api = FakeApi.new
      browser = FakeBrowser.new
      store = MemoryStore.new
      image_store = build(api: api, browser: browser, store: store)

      first = image_store.urls_for(
        media_paths: [path], media_urls: ["https://media.example/photo.png"],
        failure_screenshot_path: "failed.png")
      second = image_store.urls_for(
        media_paths: [path], media_urls: ["https://media.example/photo.png"])

      assert_equal first, second
      assert_equal 1, api.inserted.length
      assert api.inserted.first[:is_draft]
      assert_equal ["101"], api.deleted
      assert_equal 1, browser.calls.length
      assert_equal "failed.png", browser.calls.first[:screenshot]
      assert_operator store.saves, :>=, 3
    end
  end

  def test_downloads_remote_image_when_local_path_is_missing
    api = FakeApi.new
    browser = FakeBrowser.new
    fetched = []
    image_store = build(
      api: api, browser: browser, store: MemoryStore.new,
      fetcher: ->(url) { fetched << url; "downloaded" })

    urls = image_store.urls_for(
      media_paths: [], media_urls: ["https://media.example/photo.jpg"])

    assert_equal ["https://media.example/photo.jpg"], fetched
    assert_equal 1, urls.length
    assert browser.calls.first[:paths].all? { |path| File.extname(path) == ".jpg" }
  end

  def test_cleans_pending_draft_before_new_upload
    api = FakeApi.new
    browser = FakeBrowser.new
    store = MemoryStore.new("images" => {}, "pending_drafts" => ["old"])
    Dir.mktmpdir do |dir|
      path = File.join(dir, "photo.png")
      File.binwrite(path, "new")

      build(api: api, browser: browser, store: store).urls_for(
        media_paths: [path], media_urls: [])
    end

    assert_equal ["old", "101"], api.deleted
  end

  def test_rejects_non_blogger_image_url
    bad_browser = Class.new(FakeBrowser) do
      def upload(draft_id:, media_paths:, failure_screenshot_path: nil)
        path = media_paths.first
        yield(path, "https://example.test/image.png")
      end
    end.new
    api = FakeApi.new
    Dir.mktmpdir do |dir|
      path = File.join(dir, "photo.png")
      File.binwrite(path, "bad")
      error = assert_raises(RuntimeError) do
        build(api: api, browser: bad_browser, store: MemoryStore.new).urls_for(
          media_paths: [path], media_urls: [])
      end
      assert_match(/Blogger画像の公開URLを確認できません/, error.message)
    end
    assert_equal ["101"], api.deleted
  end
end
