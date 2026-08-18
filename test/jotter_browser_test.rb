require_relative "test_helper"
require "jotter_browser"

class JotterBrowserTest < Minitest::Test
  class FakeNode
    attr_reader :text

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
      @text = text
      @on_type&.call(text)
      self
    end

    def select_file(path)
      @on_select_file&.call(path)
      self
    end
  end

  class FakeBrowser
    attr_reader :goto_count, :typed_text, :media_path, :quit_called, :screenshot_call,
                :confirm_clicks

    def initialize(wrong_account_once: false, confirm_post: true, hide_browser_id: false,
                   home_requires_reset: false, confirmation_steps: 1, post_detail: true)
      @wrong_account_once = wrong_account_once
      @confirm_post = confirm_post
      @hide_browser_id = hide_browser_id
      @home_requires_reset = home_requires_reset
      @confirmation_steps = confirmation_steps
      @post_detail = post_detail
      @home_reset = false
      @goto_count = 0
      @account_open = false
      @composer_open = false
      @submitted = false
      @confirm_clicks = 0
    end

    def goto(url)
      @goto_count += 1
      @url = url
      @account_open = false
      @composer_open = false
    end

    def evaluate(script, *_args)
      case script
      when SnsMultipost::JotterBrowser::LOGGED_IN_JS
        { "loggedIn" => !@home_requires_reset || @home_reset }
      when SnsMultipost::JotterBrowser::HOME_RESET_JS
        @home_reset = true
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
        @submitted && @confirmation_steps.zero? && @confirm_post ?
          "https://jotter.me/ja-JP/jot/#new" : nil
      when SnsMultipost::JotterBrowser::AT_POST_URL_JS
        @url == _args.first
      when SnsMultipost::JotterBrowser::POST_DETAIL_JS
        @post_detail && @url == "https://jotter.me/ja-JP/jot/#new" &&
          @typed_text.to_s.include?(_args.first.to_s)
      when SnsMultipost::JotterBrowser::WALLET_STATE_JS
        if @den_verified
          return {
            "wallet" => true,
            "accountId" => "account-secret",
            "browserId" => @hide_browser_id ? nil : "browser-secret",
            "balances" => {
              "available" => "270", "unverified" => "0",
              "needsUpdate" => "0", "scheduled" => "0", "total" => "270"
            },
            "diagnostic" => []
          }
        end
        {
          "wallet" => true,
          "accountId" => "account-secret",
          "browserId" => @hide_browser_id ? nil : "browser-secret",
          "balances" => {
            "available" => "180", "unverified" => "90",
            "needsUpdate" => "0", "scheduled" => "0", "total" => "270"
          },
          "diagnostic" => []
        }
      when SnsMultipost::JotterBrowser::VERIFY_UNVERIFIED_JS
        @den_verified = true
      when SnsMultipost::JotterBrowser::MEDIA_STATE_JS
        {
          "hasInput" => @composer_open,
          "inputCount" => @composer_open ? 1 : 0,
          "accept" => "image/jpeg,image/png",
          "multiple" => true,
          "fileCount" => @media_path ? 1 : 0,
          "previewCount" => @media_path ? 1 : 0,
          "requiredDen" => @media_path ? "90" : nil,
          "denLines" => @media_path ? ["90 DEN"] : [],
          "statusLines" => []
        }
      end
    end

    def at_xpath(selector)
      return unless selector == SnsMultipost::JotterBrowser::CONFIRM_XPATH &&
                    @submitted && @confirmation_steps.positive?

      FakeNode.new(on_click: -> {
        @confirmation_steps -= 1
        @confirm_clicks += 1
      })
    end

    def at_css(selector)
      return nil unless @composer_open
      case selector
      when SnsMultipost::JotterBrowser::TEXT_SELECTOR
        FakeNode.new(on_type: ->(text) { @typed_text = text })
      when SnsMultipost::JotterBrowser::SUBMIT_SELECTOR
        FakeNode.new(on_click: -> { @submitted = true })
      when 'input[type="file"][accept*="image"]', SnsMultipost::JotterBrowser::MEDIA_SELECTOR
        FakeNode.new(on_select_file: ->(path) { @media_path = path })
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
      wallet_browser_id_timeout: 0,
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

  def test_smoke_reloads_home_when_account_panel_remains_open
    browser = FakeBrowser.new(home_requires_reset: true)

    result = client(browser).smoke

    assert_equal true, result["hasEditor"]
    assert_equal true, result["hasSubmit"]
  end

  def test_post_enters_text_selects_public_and_confirms_url
    browser = FakeBrowser.new
    result = client(browser).post(text: "Jotterテスト")

    assert_equal "Jotterテスト", browser.typed_text
    assert_equal 1, browser.confirm_clicks
    assert_equal true, result[:posted]
    assert_equal "https://jotter.me/ja-JP/jot/#new", result[:url]
  end

  def test_post_accepts_consecutive_confirmation_steps
    browser = FakeBrowser.new(confirmation_steps: 2)

    result = client(browser).post(text: "二段階確認")

    assert_equal 2, browser.confirm_clicks
    assert result[:posted]
  end

  def test_post_requires_text_on_individual_post_page
    browser = FakeBrowser.new(post_detail: false)

    error = assert_raises(RuntimeError) do
      client(browser).post(text: "個別画面確認")
    end

    assert_match(/個別画面を確認できません/, error.message)
  end

  def test_wallet_smoke_reads_ids_and_den_without_posting
    browser = FakeBrowser.new
    result = client(browser).wallet_smoke

    assert_equal "account-secret", result["accountId"]
    assert_equal "browser-secret", result["browserId"]
    assert_equal "180", result.dig("balances", "available")
    assert_equal 0, browser.confirm_clicks
  end

  def test_wallet_hold_keeps_browser_open_during_block
    browser = FakeBrowser.new
    yielded = nil
    result = client(browser).wallet_hold do |state|
      yielded = state
      refute browser.quit_called
    end

    assert_equal "browser-secret", yielded["browserId"]
    assert_equal "180", result.dig("balances", "available")
    assert_nil browser.quit_called
  end

  def test_wallet_verify_checks_identity_then_makes_den_available
    browser = FakeBrowser.new
    identity = nil
    result = client(browser).wallet_verify(
      required_den: 200, attempts: 2, verification_timeout: 0) do |state|
      identity = state["browserId"]
    end

    assert_equal "browser-secret", identity
    assert_equal "available", result["status"]
    assert_equal 1, result["attempts"]
    assert_equal "270", result.dig("after", "balances", "available")
  end

  def test_media_smoke_selects_one_image_without_posting
    Dir.mktmpdir do |dir|
      path = File.join(dir, "one.png")
      File.binwrite(path, "image")
      browser = FakeBrowser.new
      result = client(browser).media_smoke(path)

      assert_equal 1, result["fileCount"]
      assert_equal 1, result["previewCount"]
      assert_equal "90", result["requiredDen"]
      assert_equal ["90 DEN"], result["denLines"]
      assert_equal 0, browser.confirm_clicks
    end
  end

  def test_post_attaches_first_image_after_wallet_identity_and_den_check
    Dir.mktmpdir do |dir|
      first = File.join(dir, "one.png")
      second = File.join(dir, "two.png")
      File.binwrite(first, "one")
      File.binwrite(second, "two")
      browser = FakeBrowser.new
      expected = Digest::SHA256.hexdigest("jotter-wallet-v1\0browser-secret")[0, 12]

      result = client(browser).post(
        text: "画像投稿", media_paths: [first, second],
        expected_browser_id_fingerprint: expected)

      assert_equal first, browser.media_path
      assert_equal true, result[:posted]
    end
  end

  def test_image_post_can_use_confirmed_profile_when_browser_id_is_not_visible
    Dir.mktmpdir do |dir|
      path = File.join(dir, "one.png")
      File.binwrite(path, "one")
      browser = FakeBrowser.new(hide_browser_id: true)

      result = client(browser).post(
        text: "無人画像投稿", media_paths: [path],
        expected_browser_id_fingerprint: "saved-reference")

      assert_equal path, browser.media_path
      assert result[:posted]
    end
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
