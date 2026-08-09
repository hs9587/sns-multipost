require_relative "test_helper"
require "jotter_browser"

class JotterBrowserTest < Minitest::Test
  class FakeNode
    attr_reader :text

    def initialize(on_click: nil, on_type: nil)
      @on_click = on_click
      @on_type = on_type
    end

    def click
      @on_click&.call
      self
    end

    def type(text)
      @text = text
      @on_type&.call(text)
      self
    end
  end

  class FakeBrowser
    attr_reader :goto_count, :typed_text, :quit_called, :screenshot_call, :confirm_clicked

    def initialize(wrong_account_once: false, confirm_post: true)
      @wrong_account_once = wrong_account_once
      @confirm_post = confirm_post
      @goto_count = 0
      @account_open = false
      @composer_open = false
      @submitted = false
    end

    def goto(_url)
      @goto_count += 1
      @account_open = false
      @composer_open = false
    end

    def evaluate(script, *_args)
      case script
      when SnsMultipost::JotterBrowser::LOGGED_IN_JS
        { "loggedIn" => true }
      when SnsMultipost::JotterBrowser::SAVEPOINT_READY_JS
        { "ready" => true }
      when SnsMultipost::JotterBrowser::OPEN_ACCOUNT_JS
        @account_open = true
      when SnsMultipost::JotterBrowser::ACCOUNT_NAME_JS
        return nil unless @account_open
        if @wrong_account_once && @goto_count < 2
          "temporary"
        else
          "hs9587"
        end
      when SnsMultipost::JotterBrowser::OPEN_COMPOSER_JS
        @composer_open = true
      when SnsMultipost::JotterBrowser::SET_PUBLIC_JS
        @composer_open
      when SnsMultipost::JotterBrowser::POST_URLS_JS
        []
      when SnsMultipost::JotterBrowser::POST_URL_JS
        @submitted && @confirm_clicked && @confirm_post ? "https://jotter.me/ja-JP/jot/#new" : nil
      end
    end

    def at_xpath(selector)
      return unless selector == SnsMultipost::JotterBrowser::CONFIRM_XPATH && @submitted

      FakeNode.new(on_click: -> { @confirm_clicked = true })
    end

    def at_css(selector)
      return nil unless @composer_open
      case selector
      when SnsMultipost::JotterBrowser::TEXT_SELECTOR
        FakeNode.new(on_type: ->(text) { @typed_text = text })
      when SnsMultipost::JotterBrowser::SUBMIT_SELECTOR
        FakeNode.new(on_click: -> { @submitted = true })
      end
    end

    def quit
      @quit_called = true
    end

    def screenshot(path:, full:)
      @screenshot_call = { path: path, full: full }
    end
  end

  def client(browser, account_name: "hs9587")
    SnsMultipost::JotterBrowser.new(
      savepoint_url: "https://secret.example/savepoint",
      account_name: account_name,
      browser: browser,
      timeout: 0,
      auth_timeout: 0,
      confirmation_timeout: 0,
      savepoint_settle_seconds: 0,
      sleeper: ->(_seconds) {})
  end

  def test_smoke_retries_until_expected_account_and_opens_public_composer
    browser = FakeBrowser.new(wrong_account_once: true)
    result = client(browser).smoke

    assert_operator browser.goto_count, :>=, 3
    assert_equal true, result["hasEditor"]
    assert_equal true, result["hasSubmit"]
    assert_equal true, result["hasPublic"]
  end

  def test_post_enters_text_selects_public_and_confirms_url
    browser = FakeBrowser.new
    result = client(browser).post(text: "Jotterテスト")

    assert_equal "Jotterテスト", browser.typed_text
    assert_equal true, browser.confirm_clicked
    assert_equal true, result[:posted]
    assert_equal "https://jotter.me/ja-JP/jot/#new", result[:url]
  end

  def test_rejects_missing_savepoint
    error = assert_raises(RuntimeError) do
      SnsMultipost::JotterBrowser.new(savepoint_url: "")
    end
    assert_match(/savepoint_url/, error.message)
  end

  def test_failure_captures_screenshot
    Dir.mktmpdir do |dir|
      browser = FakeBrowser.new(confirm_post: false)
      path = File.join(dir, "failed", "job.png")
      assert_raises(RuntimeError) do
        client(browser).post(text: "失敗", failure_screenshot_path: path)
      end
      assert_equal({ path: path, full: false }, browser.screenshot_call)
    end
  end
end
