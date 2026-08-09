require_relative "test_helper"
require "mixi2_browser"

class Mixi2BrowserTest < Minitest::Test
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

    def select_file(paths)
      @on_select_file&.call(paths)
      self
    end

    def evaluate(_script)
      true
    end
  end

  class FakeBrowser
    attr_reader :url, :quit_called, :text, :media_paths

    def initialize
      @composer_open = false
      @submitted = false
    end

    def goto(url)
      @url = url
    end

    def evaluate(script, *_args)
      case script
      when SnsMultipost::Mixi2Browser::STATE_JS
        { "url" => @url, "loggedIn" => true }
      when SnsMultipost::Mixi2Browser::CLOSE_COMPOSER_JS
        @composer_open = false
        true
      when SnsMultipost::Mixi2Browser::COMPOSER_JS
        { "opened" => @composer_open, "hasEditor" => true, "hasSubmit" => true,
          "hasMedia" => true, "mediaMultiple" => true }
      when SnsMultipost::Mixi2Browser::SUBMIT_READY_JS
        !@text.to_s.empty?
      when SnsMultipost::Mixi2Browser::POST_URL_JS
        @submitted ? "https://mixi.social/@me/posts/123" : nil
      end
    end

    def at_css(selector)
      case selector
      when SnsMultipost::Mixi2Browser::EDITOR_SELECTOR
        FakeNode.new(on_type: ->(text) { @text = text })
      when SnsMultipost::Mixi2Browser::MEDIA_SELECTOR
        FakeNode.new(on_select_file: ->(path) { (@media_paths ||= []) << path })
      when SnsMultipost::Mixi2Browser::SUBMIT_SELECTOR
        FakeNode.new(on_click: -> { @submitted = true; @composer_open = false })
      end
    end

    def xpath(selector)
      return [] unless selector == SnsMultipost::Mixi2Browser::POST_BUTTON_XPATH
      [FakeNode.new(on_click: -> { @composer_open = true })]
    end

    def quit
      @quit_called = true
    end
  end

  def test_smoke_checks_login_and_composer_without_posting
    browser = FakeBrowser.new
    result = SnsMultipost::Mixi2Browser.new(
      browser: browser, timeout: 0, sleeper: ->(_seconds) {}).smoke

    assert_equal SnsMultipost::Mixi2Browser::HOME_URL, browser.url
    assert result["opened"]
    assert result["hasEditor"]
    assert result["hasSubmit"]
    assert result["mediaMultiple"]
    refute browser.quit_called
  end

  def test_smoke_rejects_logged_out_session
    browser = FakeBrowser.new
    def browser.evaluate(script)
      return { "url" => url, "loggedIn" => false } if script == SnsMultipost::Mixi2Browser::STATE_JS
      super
    end

    error = assert_raises(RuntimeError) do
      SnsMultipost::Mixi2Browser.new(
        browser: browser, timeout: 0, sleeper: ->(_seconds) {}).smoke
    end
    assert_match(/ログインしていません/, error.message)
  end

  def test_post_enters_text_attaches_media_and_confirms_completion
    browser = FakeBrowser.new
    result = SnsMultipost::Mixi2Browser.new(
      browser: browser, timeout: 0, sleeper: ->(_seconds) {}).post(
        text: "おはようございます", media_paths: ["one.jpg", "two.png"])

    assert_equal "おはようございます", browser.text
    assert_equal ["one.jpg", "two.png"], browser.media_paths
    assert_equal true, result[:posted]
    assert_equal "https://mixi.social/@me/posts/123", result[:url]
  end
end
