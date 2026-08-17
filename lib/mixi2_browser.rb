require_relative "browser_profile"
require "fileutils"

module SnsMultipost
  class Mixi2Browser
    HOME_URL = "https://mixi.social/home".freeze
    EDITOR_SELECTOR = '.tiptap.ProseMirror[contenteditable="true"]'.freeze
    MEDIA_SELECTOR = 'input[type="file"]'.freeze
    SUBMIT_SELECTOR = 'button[type="submit"][aria-label="送信"]'.freeze
    POST_BUTTON_XPATH = '//button[normalize-space(.)="ポスト"]'.freeze
    MEDIA_SETTLE_SECONDS = 30

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
        const excluded = new Set(arguments[1] || []);
        const article = Array.from(document.querySelectorAll('article'))
          .find((candidate) => {
            if (!candidate.textContent.includes(expected)) return false;
            const link = candidate.querySelector('a[href*="/posts/"]');
            const url = link && new URL(link.getAttribute('href'), location.origin).href;
            return url && !excluded.has(url);
          });
        const link = article && article.querySelector('a[href*="/posts/"]');
        return link ? new URL(link.getAttribute('href'), location.origin).href : null;
      })()
    JS

    POST_PROCESSING_JS = <<~'JS'.freeze
      (() => {
        const text = (document.body?.innerText || '').replace(/\s+/g, ' ');
        return text.includes('画像をアップロードしています') ||
          /uploading\s+(?:the\s+)?image/i.test(text);
      })()
    JS

    ATTACHMENT_STATE_JS = <<~'JS'.freeze
      (() => {
        const dialogs = Array.from(document.querySelectorAll('[role="dialog"]'));
        const dialog = dialogs.find((candidate) =>
          candidate.getClientRects().length > 0 &&
          candidate.querySelector('button[type="submit"][aria-label="送信"]') &&
          candidate.querySelector('[contenteditable="true"]'));
        if (!dialog) return { files: 0, previews: 0 };
        const input = dialog.querySelector('input[type="file"]');
        const previews = Array.from(dialog.querySelectorAll('img, video')).filter((media) => {
          const rect = media.getBoundingClientRect();
          return rect.width > 64 && rect.height > 64;
        });
        return {
          files: input ? input.files.length : 0,
          previews: previews.length,
          previewSources: previews.map((media) => {
            const source = media.currentSrc || media.src || '';
            return source.startsWith('blob:') ? 'blob' :
              source.startsWith('data:') ? 'data' :
              source.startsWith('http') ? 'http' : 'other';
          }),
          busy: dialog.querySelectorAll('[aria-busy="true"], [data-loading="true"]').length,
          editors: Array.from(dialog.querySelectorAll('[contenteditable="true"]'))
            .map((node) => node.getClientRects().length > 0),
          submits: Array.from(dialog.querySelectorAll('button[type="submit"]'))
            .map((node) => node.getClientRects().length > 0),
          inputs: Array.from(dialog.querySelectorAll('input[type="file"]')).map((node) => ({
            accept: node.accept,
            multiple: node.multiple,
            parentVisible: !!node.parentElement && node.parentElement.getClientRects().length > 0
          }))
        };
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
      state, composer, = open_composer

      raise "mixi2の投稿画面を閉じられません" unless browser.evaluate(CLOSE_COMPOSER_JS)
      composer.merge("url" => state["url"])
    ensure
      browser.quit if @owns_browser && @browser
    end

    def post(text:, media_paths: [], failure_screenshot_path: nil)
      _, _, composer = open_composer

      editor = composer.at_css(EDITOR_SELECTOR)
      raise "mixi2の本文欄が見つかりません" unless editor
      editor.click.type(text)

      unless media_paths.empty?
        media_paths.each do |path|
          attach_media(composer, path)
        end
      end

      ready = wait_for { browser.evaluate(SUBMIT_READY_JS) }
      raise "mixi2の送信ボタンが有効になりません" unless ready

      existing_urls = browser.evaluate(POST_URLS_JS, text[0, 40])

      submit = composer.at_css(SUBMIT_SELECTOR)
      raise "mixi2の送信ボタンが見つかりません" unless submit
      submit.click

      closed = wait_for { !browser.evaluate(COMPOSER_JS)["opened"] }
      raise "mixi2の投稿完了を確認できません" unless closed

      confirmation_timeout = media_paths.empty? ? @timeout : [@timeout * 8, 120].max
      unless media_paths.empty?
        uploaded = wait_for(timeout: confirmation_timeout) do
          !browser.evaluate(POST_PROCESSING_JS)
        end
        raise "mixi2の投稿後画像アップロードが完了しません" unless uploaded
      end

      url = wait_for(timeout: confirmation_timeout) do
        browser.evaluate(POST_URL_JS, text[0, 40], existing_urls)
      end
      unless url
        browser.goto(HOME_URL)
        url = wait_for(timeout: confirmation_timeout) do
          browser.evaluate(POST_URL_JS, text[0, 40], existing_urls)
        end
      end
      raise "mixi2の新しい投稿を確認できません" unless url
      { posted: true, url: url }
    rescue StandardError
      capture_failure_screenshot(failure_screenshot_path)
      raise
    ensure
      browser.quit if @owns_browser && @browser
    end

    POST_URLS_JS = <<~'JS'.freeze
      (() => {
        const expected = arguments[0];
        return Array.from(document.querySelectorAll('article'))
          .filter((candidate) => candidate.textContent.includes(expected))
          .map((candidate) => candidate.querySelector('a[href*="/posts/"]'))
          .filter(Boolean)
          .map((link) => new URL(link.getAttribute('href'), location.origin).href);
      })()
    JS

    def media_smoke(media_path)
      _, _, composer = open_composer
      state = attach_media(composer, media_path)
      raise "mixi2の投稿画面を閉じられません" unless browser.evaluate(CLOSE_COMPOSER_JS)
      state
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

      composer_node = wait_for { active_composer_node }
      raise "mixi2の表示中投稿ダイアログを特定できません" unless composer_node

      [state, composer, composer_node]
    end

    def active_composer_node
      browser.css('[role="dialog"]').find do |candidate|
        candidate.evaluate(<<~'JS')
          this.getClientRects().length > 0 &&
          !!this.querySelector('button[type="submit"][aria-label="送信"]') &&
          !!this.querySelector('[contenteditable="true"]')
        JS
      rescue StandardError
        false
      end
    end

    def attach_media(composer, path)
      before = browser.evaluate(ATTACHMENT_STATE_JS)
      media = composer.at_css(MEDIA_SELECTOR)
      raise "mixi2のメディア入力が見つかりません" unless media
      baseline_connections = browser.network.pending_connections
      media.select_file(path)
      @sleeper.call(0.2)
      attached = wait_for do
        state = browser.evaluate(ATTACHMENT_STATE_JS)
        state if state["previews"] > before["previews"]
      end
      raise "mixi2の画像プレビューを確認できません: #{path}" unless attached
      idle = browser.network.wait_for_idle(
        connections: baseline_connections,
        duration: 0.1,
        timeout: [@timeout * 2, 30].max)
      raise "mixi2の画像アップロードが完了しません: #{path}" unless idle
          # プレビューはローカルの blob URL ですぐ表示されるが、mixi2 側が
          # 投稿用データとして画像を取り込むまで時間がかかることがある。
          @sleeper.call(MEDIA_SETTLE_SECONDS)
      attached
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
