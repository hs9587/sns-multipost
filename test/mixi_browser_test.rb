require_relative "test_helper"
require "mixi_browser"

class MixiBrowserTest < Minitest::Test
  class TransientNodeNotFoundError < StandardError; end

  class FakeNode
    def initialize(on_click: nil, on_type: nil, on_select_file: nil)
      @on_click = on_click
      @on_type = on_type
      @on_select_file = on_select_file
    end

    def click
      @on_click&.call
      self
    end

    def type(text)
      @on_type&.call(text)
      self
    end

    def select_file(path)
      @on_select_file&.call(path)
      self
    end
  end

  class FakeBrowser
    attr_reader :url, :text, :media_path, :screenshot_call

    def initialize(post_url: true, stale_actions: [])
      @post_url = post_url
      @stale_actions = stale_actions.dup
      @photo_open = false
      @posted = false
    end

    def goto(url)
      @url = url
    end

    def evaluate(script, *_args)
      case script
      when SnsMultipost::MixiBrowser::STATE_JS
        { "url" => @url, "loggedIn" => true, "hasText" => true, "hasSubmit" => true }
      when SnsMultipost::MixiBrowser::SET_TEXT_JS
        @text = _args.first
        true
      when SnsMultipost::MixiBrowser::OPEN_PHOTO_INPUT_JS
        @photo_open = true
      when SnsMultipost::MixiBrowser::CLICK_SUBMIT_JS
        @posted = true
      when SnsMultipost::MixiBrowser::FILE_STATE_JS
        { "present" => @photo_open, "files" => @media_path ? 1 : 0 }
      when SnsMultipost::MixiBrowser::POST_URLS_JS
        []
      when SnsMultipost::MixiBrowser::POST_URL_JS
        @posted && @post_url ? "https://mixi.jp/view_voice.pl?id=123" : nil
      end
    end

    def at_css(selector)
      case selector
      when SnsMultipost::MixiBrowser::TEXT_SELECTOR
        raise_stale_once(:editor_find)
        FakeNode.new(
          on_click: -> { raise_stale_once(:editor) },
          on_type: ->(text) { @text = text })
      when SnsMultipost::MixiBrowser::SUBMIT_SELECTOR
        raise_stale_once(:submit_find)
        FakeNode.new(on_click: -> { raise_stale_once(:submit); @posted = true })
      when SnsMultipost::MixiBrowser::PHOTO_INPUT_SELECTOR
        raise_stale_once(:media_find)
        @photo_open && FakeNode.new(on_select_file: ->(path) {
          raise_stale_once(:media)
          @media_path = path
        })
      end
    end

    def at_xpath(selector)
      return unless selector == SnsMultipost::MixiBrowser::PHOTO_LINK_XPATH
      raise_stale_once(:photo_link_find)
      FakeNode.new(on_click: -> { raise_stale_once(:photo_link); @photo_open = true })
    end

    def screenshot(path:, full:)
      @screenshot_call = { path: path, full: full }
    end

    private

    def raise_stale_once(action)
      index = @stale_actions.index(action)
      return unless index

      @stale_actions.delete_at(index)
      raise TransientNodeNotFoundError, "stale #{action}"
    end
  end

  def test_smoke_checks_form_without_posting
    browser = FakeBrowser.new
    result = SnsMultipost::MixiBrowser.new(
      browser: browser, timeout: 0, sleeper: ->(_seconds) {}).smoke

    assert_equal SnsMultipost::MixiBrowser::HOME_URL, browser.url
    assert result["hasText"]
    assert result["hasSubmit"]
    assert result["hasMedia"]
    assert_nil browser.text
  end

  def test_post_enters_text_attaches_first_media_and_returns_new_url
    browser = FakeBrowser.new
    result = SnsMultipost::MixiBrowser.new(
      browser: browser, timeout: 0, sleeper: ->(_seconds) {}).post(
        text: "テスト", media_paths: ["one.png"])

    assert_equal "テスト", browser.text
    assert_equal "one.png", browser.media_path
    assert result[:posted]
    assert_equal "https://mixi.jp/view_voice.pl?id=123", result[:url]
  end

  def test_post_uses_atomic_dom_actions_and_reacquires_media_input
    browser = FakeBrowser.new(stale_actions: [:media_find] + Array.new(6, :media))

    result = SnsMultipost::MixiBrowser.new(
      browser: browser, timeout: 0, sleeper: ->(_seconds) {}).post(
        text: "再取得テスト", media_paths: ["one.png"])

    assert_equal "再取得テスト", browser.text
    assert_equal "one.png", browser.media_path
    assert result[:posted]
  end

  def test_post_captures_screenshot_when_new_voice_is_missing
    Dir.mktmpdir do |dir|
      browser = FakeBrowser.new(post_url: false)
      path = File.join(dir, "failed", "job.png")

      error = assert_raises(RuntimeError) do
        SnsMultipost::MixiBrowser.new(
          browser: browser, timeout: 0, sleeper: ->(_seconds) {}).post(
            text: "失敗", failure_screenshot_path: path)
      end

      assert_match(/新しいつぶやきを確認できません/, error.message)
      assert_equal({ path: path, full: false }, browser.screenshot_call)
    end
  end
end
