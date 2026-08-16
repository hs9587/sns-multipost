require "fileutils"
require_relative "browser_profile"

module SnsMultipost
  class MixiBrowser
    HOME_URL = "https://mixi.jp/home.pl".freeze
    TEXT_SELECTOR = "#voiceComment".freeze
    SUBMIT_SELECTOR = "#voicePostSubmit".freeze
    PHOTO_LINK_XPATH = "//a[@title='写真を追加']".freeze
    PHOTO_INPUT_SELECTOR = "input[type='file'][name='photo']".freeze
    NODE_ACTION_ATTEMPTS = 3

    STATE_JS = <<~'JS'.freeze
      (() => ({
        url: location.href,
        loggedIn: !!document.querySelector('#voiceComment')
      }))()
    JS

    POST_URLS_JS = <<~'JS'.freeze
      (() => {
        const expected = arguments[0];
        return Array.from(document.querySelectorAll('p.description'))
          .filter((body) => body.textContent.includes(expected))
          .map((body) => (body.closest('li, article') || body.parentElement)
            ?.querySelector('a[href*="view_voice.pl"]'))
          .filter(Boolean)
          .map((link) => new URL(link.getAttribute('href'), location.origin).href);
      })()
    JS

    POST_URL_JS = <<~'JS'.freeze
      (() => {
        const expected = arguments[0];
        const excluded = new Set(arguments[1] || []);
        return Array.from(document.querySelectorAll('p.description'))
          .filter((body) => body.textContent.includes(expected))
          .map((body) => (body.closest('li, article') || body.parentElement)
            ?.querySelector('a[href*="view_voice.pl"]'))
          .filter(Boolean)
          .map((link) => new URL(link.getAttribute('href'), location.origin).href)
          .find((url) => !excluded.has(url)) || null;
      })()
    JS

    FILE_STATE_JS = <<~'JS'.freeze
      (() => {
        const input = document.querySelector("input[type='file'][name='photo']");
        return { present: !!input, files: input ? input.files.length : 0 };
      })()
    JS

    def initialize(browser: nil, profile: BrowserProfile.new, headless: false,
                   timeout: 20, sleeper: ->(seconds) { sleep seconds })
      @browser = browser
      @profile = profile
      @headless = headless
      @timeout = timeout
      @sleeper = sleeper
      @owns_browser = browser.nil?
    end

    def smoke
      state = open_home
      with_fresh_node(-> { browser.at_css(TEXT_SELECTOR) }, "mixiのつぶやき入力欄が見つかりません") do |editor|
        editor.click
      end
      open_photo_input
      file_state = wait_for { browser.evaluate(FILE_STATE_JS).then { |s| s if s["present"] } }
      raise "mixiの写真入力が見つかりません" unless file_state

      { "url" => state["url"], "hasText" => true, "hasSubmit" => !!browser.at_css(SUBMIT_SELECTOR),
        "hasMedia" => true }
    ensure
      browser.quit if @owns_browser && @browser
    end

    def post(text:, media_paths: [], failure_screenshot_path: nil)
      open_home
      with_fresh_node(-> { browser.at_css(TEXT_SELECTOR) }, "mixiのつぶやき入力欄が見つかりません") do |editor|
        editor.click.type(text)
      end

      unless media_paths.empty?
        open_photo_input
        with_fresh_node(-> { browser.at_css(PHOTO_INPUT_SELECTOR) }, "mixiの写真入力が見つかりません") do |media|
          media.select_file(media_paths.first)
        end
        attached = wait_for do
          state = browser.evaluate(FILE_STATE_JS)
          state if state["files"] == 1
        end
        raise "mixiの画像選択を確認できません: #{media_paths.first}" unless attached
      end

      existing_urls = browser.evaluate(POST_URLS_JS, text[0, 40])
      with_fresh_node(-> { browser.at_css(SUBMIT_SELECTOR) }, "mixiのつぶやくボタンが見つかりません") do |submit|
        submit.click
      end

      confirmation_timeout = media_paths.empty? ? @timeout : [@timeout * 3, 60].max
      url = wait_for(timeout: confirmation_timeout) do
        browser.evaluate(POST_URL_JS, text[0, 40], existing_urls)
      end
      unless url
        browser.goto(HOME_URL)
        url = wait_for { browser.evaluate(POST_URL_JS, text[0, 40], existing_urls) }
      end
      raise "mixiの新しいつぶやきを確認できません" unless url
      { posted: true, url: url }
    rescue StandardError
      capture_failure_screenshot(failure_screenshot_path)
      raise
    ensure
      browser.quit if @owns_browser && @browser
    end

    private

    def open_home
      browser.goto(HOME_URL)
      last_state = nil
      state = wait_for do
        last_state = browser.evaluate(STATE_JS)
        last_state if last_state["loggedIn"]
      end
      unless state
        raise "mixiにログインしていません（現在URL: #{last_state && last_state['url']}）。" \
              "ruby bin/browser_login mixi を実行してください"
      end
      raise "mixiのつぶやき入力欄が見つかりません" unless browser.at_css(TEXT_SELECTOR)
      state
    end

    def open_photo_input
      return if browser.at_css(PHOTO_INPUT_SELECTOR)

      with_fresh_node(-> { browser.at_xpath(PHOTO_LINK_XPATH) }, "mixiの写真追加ボタンが見つかりません") do |link|
        link.click
      end
    end

    def with_fresh_node(finder, missing_message)
      last_error = nil
      NODE_ACTION_ATTEMPTS.times do
        node = wait_for { finder.call }
        raise missing_message unless node

        begin
          return yield node
        rescue StandardError => e
          raise unless node_not_found_error?(e)

          last_error = e
          @sleeper.call(0.2)
        end
      end
      raise last_error
    end

    def node_not_found_error?(error)
      error.class.name.end_with?("NodeNotFoundError")
    end

    def capture_failure_screenshot(path)
      return false if path.to_s.empty? || !@browser

      FileUtils.mkdir_p(File.dirname(path))
      browser.screenshot(path: path, full: false)
      true
    rescue StandardError
      false
    end

    def browser
      @browser ||= begin
        require "ferrum"
        Ferrum::Browser.new(
          browser_path: @profile.chrome_path,
          browser_options: { "user-data-dir" => @profile.profile_dir("mixi") },
          headless: @headless,
          incognito: false,
          timeout: @timeout,
          process_timeout: 60,
          pending_connection_errors: false)
      end
    end

    def wait_for(timeout: @timeout)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        value = yield
        return value if value
        return nil if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        @sleeper.call(0.2)
      end
    end
  end
end
