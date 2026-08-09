require_relative "browser_profile"

module SnsMultipost
  class Mixi2Browser
    HOME_URL = "https://mixi.social/home".freeze
    EDITOR_SELECTOR = '.tiptap.ProseMirror[contenteditable="true"]'.freeze
    MEDIA_SELECTOR = 'input[type="file"]'.freeze
    SUBMIT_SELECTOR = 'button[type="submit"][aria-label="送信"]'.freeze
    POST_BUTTON_XPATH = '//button[normalize-space(.)="ポスト"]'.freeze

    STATE_JS = <<~'JS'.freeze
      (() => ({
        url: location.href,
        loggedIn: Array.from(document.querySelectorAll('button'))
          .some((button) => button.textContent.trim() === 'ポスト')
      }))()
    JS

    COMPOSER_JS = <<~'JS'.freeze
      (() => {
        const editor = document.querySelector('.tiptap.ProseMirror[contenteditable="true"]');
        const submit = document.querySelector('button[type="submit"][aria-label="送信"]');
        if (!editor || !submit) return { opened: false };
        const media = document.querySelector('input[type="file"]');
        return {
          opened: true,
          hasEditor: true,
          hasSubmit: true,
          hasMedia: !!media,
          mediaMultiple: !!media && media.multiple
        };
      })()
    JS

    CLOSE_COMPOSER_JS = <<~'JS'.freeze
      (() => {
        const dialogs = Array.from(document.querySelectorAll('[role="dialog"]'));
        const dialog = dialogs.find((candidate) =>
          candidate.querySelector('button[type="submit"][aria-label="送信"]'));
        if (!dialog) return false;
        const close = Array.from(dialog.querySelectorAll('button'))
          .find((button) => button.textContent.trim() === '閉じる');
        if (!close) return false;
        close.click();
        return true;
      })()
    JS

    SUBMIT_READY_JS = <<~'JS'.freeze
      (() => {
        const submit = document.querySelector('button[type="submit"][aria-label="送信"]');
        return !!submit && !submit.disabled;
      })()
    JS

    POST_URL_JS = <<~'JS'.freeze
      (() => {
        const expected = arguments[0];
        const article = Array.from(document.querySelectorAll('article'))
          .find((candidate) => candidate.textContent.includes(expected));
        const link = article && article.querySelector('a[href*="/posts/"]');
        return link ? new URL(link.getAttribute('href'), location.origin).href : null;
      })()
    JS

    def initialize(browser: nil, profile: BrowserProfile.new, headless: false,
                   timeout: 15, sleeper: ->(seconds) { sleep seconds })
      @browser = browser
      @profile = profile
      @headless = headless
      @timeout = timeout
      @sleeper = sleeper
      @owns_browser = browser.nil?
    end

    def smoke
      state, composer = open_composer

      raise "mixi2の投稿画面を閉じられません" unless browser.evaluate(CLOSE_COMPOSER_JS)
      composer.merge("url" => state["url"])
    ensure
      browser.quit if @owns_browser && @browser
    end

    def post(text:, media_paths: [])
      open_composer

      editor = browser.at_css(EDITOR_SELECTOR)
      raise "mixi2の本文欄が見つかりません" unless editor
      editor.click.type(text)

      unless media_paths.empty?
        media_paths.each do |path|
          media = browser.at_css(MEDIA_SELECTOR)
          raise "mixi2のメディア入力が見つかりません" unless media
          baseline_connections = browser.network.pending_connections
          media.select_file(path)
          @sleeper.call(0.2)
          idle = browser.network.wait_for_idle(
            connections: baseline_connections,
            duration: 0.1,
            timeout: [@timeout * 2, 30].max)
          raise "mixi2の画像アップロードが完了しません: #{path}" unless idle
          @sleeper.call(1)
        end
      end

      ready = wait_for { browser.evaluate(SUBMIT_READY_JS) }
      raise "mixi2の送信ボタンが有効になりません" unless ready

      submit = browser.at_css(SUBMIT_SELECTOR)
      raise "mixi2の送信ボタンが見つかりません" unless submit
      submit.click

      closed = wait_for { !browser.evaluate(COMPOSER_JS)["opened"] }
      raise "mixi2の投稿完了を確認できません" unless closed

      @sleeper.call(0.5)
      url = browser.evaluate(POST_URL_JS, text[0, 40])
      { posted: true, url: url }
    ensure
      browser.quit if @owns_browser && @browser
    end

    private

    def open_composer
      browser.goto(HOME_URL)
      last_state = nil
      state = wait_for do
        last_state = browser.evaluate(STATE_JS)
        last_state if last_state["loggedIn"]
      end
      unless state
        current_url = last_state && last_state["url"]
        raise "mixi2にログインしていません（現在URL: #{current_url}）。" \
              "ruby bin/browser_login mixi2 を実行してください"
      end

      post_button = wait_for do
        browser.xpath(POST_BUTTON_XPATH).find do |candidate|
          candidate.evaluate("this.getClientRects().length > 0")
        rescue StandardError
          false
        end
      end
      raise "mixi2のポストボタンが見つかりません" unless post_button
      post_button.click
      last_composer = nil
      composer = wait_for do
        last_composer = browser.evaluate(COMPOSER_JS)
        last_composer if last_composer["opened"]
      end
      raise "mixi2の投稿画面を確認できません: #{last_composer.inspect}" unless composer

      [state, composer]
    end

    def browser
      @browser ||= begin
        require "ferrum"
        Ferrum::Browser.new(
          browser_path: @profile.chrome_path,
          browser_options: {
            "user-data-dir" => @profile.profile_dir("mixi2")
          },
          headless: @headless,
          incognito: false,
          timeout: @timeout,
          process_timeout: 60,
          pending_connection_errors: false)
      end
    end

    def wait_for
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
      loop do
        value = yield
        return value if value
        return nil if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        @sleeper.call(0.2)
      end
    end
  end
end
