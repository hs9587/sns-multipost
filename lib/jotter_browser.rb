require "fileutils"
require "net/http"
require "socket"
require "uri"
require_relative "browser_profile"

module SnsMultipost
  class JotterBrowser
    HOME_URL = "https://jotter.me/ja-JP/".freeze
    TEXT_SELECTOR = 'textarea[name="text"]'.freeze
    SUBMIT_SELECTOR = 'button[type="submit"]'.freeze
    CONFIRM_XPATH = "//button[normalize-space()='Ok']".freeze
    SAVEPOINT_ATTEMPTS = 4
    SAVEPOINT_SETTLE_SECONDS = 30
    AUTH_TIMEOUT = 40

    LOGGED_IN_JS = <<~'JS'.freeze
      (() => ({
        loggedIn: !location.pathname.includes('/welcome') &&
          !!document.querySelector('a[href="/ja-JP/wallet/"]') &&
          !!document.querySelector('input[type="image"].user-face')
      }))()
    JS

    SAVEPOINT_READY_JS = <<~'JS'.freeze
      (() => {
        const welcome = location.pathname.includes('/welcome');
        const hashPresent = location.hash !== '';
        const hasWallet = !!document.querySelector('a[href="/ja-JP/wallet/"]');
        const hasUserFace = !!document.querySelector('input[type="image"].user-face');
        return {
          ready: !welcome && hasWallet && hasUserFace,
          welcome: welcome,
          hashPresent: hashPresent,
          hasWallet: hasWallet,
          hasUserFace: hasUserFace,
          documentReady: document.readyState
        };
      })()
    JS

    OPEN_ACCOUNT_JS = <<~'JS'.freeze
      (() => {
        const el = Array.from(document.querySelectorAll('input[type="image"].user-face'))
          .find((node) => node.offsetWidth || node.offsetHeight);
        if (!el) return false;
        el.click();
        return true;
      })()
    JS

    ACCOUNT_NAME_JS = <<~'JS'.freeze
      (() => {
        const inputs = Array.from(document.querySelectorAll('input'))
          .filter((node) => (node.offsetWidth || node.offsetHeight) &&
            !['button', 'image', 'file', 'submit', 'search'].includes(node.type));
        const named = inputs.find((node) => node.labels &&
          Array.from(node.labels).some((label) => label.textContent.trim() === 'Name'));
        const candidate = named || inputs.find((node) => node.placeholder && !node.closest('nav'));
        return candidate ? candidate.value : null;
      })()
    JS

    OPEN_COMPOSER_JS = <<~'JS'.freeze
      (() => {
        const el = Array.from(document.querySelectorAll('nav input[type="button"]:not([title])'))
          .find((node) => node.offsetWidth || node.offsetHeight);
        if (!el) return false;
        el.click();
        return true;
      })()
    JS

    SET_PUBLIC_JS = <<~'JS'.freeze
      (() => {
        const select = document.querySelector('select');
        if (!select || !Array.from(select.options).some((option) => option.value === 'auth')) return false;
        select.value = 'auth';
        select.dispatchEvent(new Event('input', { bubbles: true }));
        select.dispatchEvent(new Event('change', { bubbles: true }));
        return select.value === 'auth';
      })()
    JS

    POST_URLS_JS = <<~'JS'.freeze
      (() => Array.from(document.querySelectorAll('a[href*="/ja-JP/jot/#"]'))
        .map((link) => new URL(link.getAttribute('href'), location.origin).href))()
    JS

    POST_URL_JS = <<~'JS'.freeze
      (() => {
        const expected = arguments[0];
        const excluded = new Set(arguments[1] || []);
        if (location.pathname.includes('/jot/') && location.hash && !excluded.has(location.href)) {
          return location.href;
        }
        const paragraphs = Array.from(document.querySelectorAll('p'))
          .filter((body) => body.textContent.includes(expected));
        for (const body of paragraphs) {
          let scope = body;
          for (let i = 0; i < 5 && scope; i += 1, scope = scope.parentElement) {
            const link = scope.querySelector && scope.querySelector('a[href*="/ja-JP/jot/#"]');
            if (!link) continue;
            const url = new URL(link.getAttribute('href'), location.origin).href;
            if (!excluded.has(url)) return url;
          }
        }
        return null;
      })()
    JS

    def initialize(savepoint_url:, account_name: nil, browser: nil,
                   profile: BrowserProfile.new, headless: false, timeout: 20,
                   auth_timeout: AUTH_TIMEOUT, confirmation_timeout: 40,
                   savepoint_settle_seconds: SAVEPOINT_SETTLE_SECONDS,
                   logger: nil,
                   sleeper: ->(seconds) { sleep seconds })
      @savepoint_url = savepoint_url.to_s.strip
      @account_name = account_name.to_s.strip
      @browser = browser
      @profile = profile
      @headless = headless
      @timeout = timeout
      @auth_timeout = auth_timeout
      @confirmation_timeout = confirmation_timeout
      @savepoint_settle_seconds = savepoint_settle_seconds
      @logger = logger
      @sleeper = sleeper
      @owns_browser = browser.nil?
      raise "Jotterのsavepoint_urlが未設定です" if @savepoint_url.empty?
    end

    def smoke
      open_authenticated_home
      raise "Jotterの投稿フォームを開けません" unless safe_evaluate(OPEN_COMPOSER_JS)
      editor = wait_for { safe_at_css(TEXT_SELECTOR) }
      submit = wait_for { safe_at_css(SUBMIT_SELECTOR) }
      public_option = safe_evaluate(SET_PUBLIC_JS)
      { "hasEditor" => !!editor, "hasSubmit" => !!submit, "hasPublic" => !!public_option }
    ensure
      close_owned_browser
    end

    def post(text:, failure_screenshot_path: nil)
      open_authenticated_home
      existing_urls = safe_evaluate(POST_URLS_JS) || []
      raise "Jotterの投稿フォームを開けません" unless safe_evaluate(OPEN_COMPOSER_JS)

      editor = wait_for { safe_at_css(TEXT_SELECTOR) }
      raise "Jotterの本文入力欄が見つかりません" unless editor
      editor.click.type(text)
      raise "Jotterの公開範囲を「公開」にできません" unless safe_evaluate(SET_PUBLIC_JS)

      submit = wait_for { safe_at_css(SUBMIT_SELECTOR) }
      raise "JotterのPostボタンが見つかりません" unless submit
      submit.click
      confirm = wait_for(timeout: [@timeout, 10].min) { safe_at_xpath(CONFIRM_XPATH) }
      confirm.click if confirm

      expected = text[0, 40]
      url = wait_for(timeout: @confirmation_timeout) do
        safe_evaluate(POST_URL_JS, expected, existing_urls)
      end
      raise "Jotterの新しい公開投稿を確認できません" unless url
      { posted: true, url: url }
    rescue StandardError
      capture_failure_screenshot(failure_screenshot_path)
      raise
    ensure
      close_owned_browser
    end

    private

    def open_authenticated_home
      SAVEPOINT_ATTEMPTS.times do |index|
        status("Jotter: セーブポイント復元を試行 #{index + 1}/#{SAVEPOINT_ATTEMPTS}")
        if @owns_browser
          launch_uncontrolled_savepoint
        else
          goto_safely(@savepoint_url)
          status("Jotter: 暗号処理のため#{@savepoint_settle_seconds}秒間、画面へ触れずに待機")
          @sleeper.call(@savepoint_settle_seconds)
        end
        last_state = nil
        ready = wait_for(timeout: @auth_timeout) do
          last_state = safe_evaluate(SAVEPOINT_READY_JS)
          last_state && last_state["ready"]
        end
        unless ready
          status("Jotter: 復元完了後のホーム画面を確認できません")
          if last_state
            status("Jotter: 状態 hash=#{last_state['hashPresent'] ? 'あり' : 'なし'} " \
                   "welcome=#{last_state['welcome'] ? 'はい' : 'いいえ'} " \
                   "wallet=#{last_state['hasWallet'] ? 'あり' : 'なし'} " \
                   "user-face=#{last_state['hasUserFace'] ? 'あり' : 'なし'} " \
                   "document=#{last_state['documentReady']}")
          else
            status("Jotter: 画面状態の取得自体がタイムアウトしました")
          end
          next
        end
        status("Jotter: 復元完了後のホーム画面を確認")
        @sleeper.call(1)
        next unless correct_account?

        goto_safely(HOME_URL)
        home_ready = wait_for(timeout: @auth_timeout) do
          state = safe_evaluate(LOGGED_IN_JS)
          state && state["loggedIn"]
        end
        if home_ready
          status("Jotter: #{@account_name.empty? ? 'ログイン済み' : @account_name} を確認")
          return true
        end
        status("Jotter: 本人確認後のホーム再表示に失敗")
      end
      suffix = @account_name.empty? ? "" : "（期待するアカウント: #{@account_name}）"
      raise "Jotterのセーブポイントを復元できません#{suffix}"
    end

    def correct_account?
      return true if @account_name.empty?
      unless safe_evaluate(OPEN_ACCOUNT_JS)
        status("Jotter: アカウント設定を開けません")
        return false
      end

      name = wait_for(timeout: @auth_timeout) { safe_evaluate(ACCOUNT_NAME_JS) }
      unless name
        status("Jotter: アカウント表示名を確認できません")
        return false
      end
      if name == @account_name
        status("Jotter: 期待するアカウント表示名と一致")
        true
      else
        status("Jotter: 別のアカウントが復元されたため再試行")
        false
      end
    end

    def status(message)
      @logger&.call(message)
    end

    def goto_safely(url)
      if browser.respond_to?(:page) && browser.page.respond_to?(:client)
        browser.page.client.command("Page.navigate", async: true, url: url)
      else
        browser.goto(url)
      end
      true
    rescue StandardError
      # Jotterのセーブポイント処理はload完了前にSPA遷移することがある。
      # 現在画面は後続のポーリングで判定する。
      false
    end

    def launch_uncontrolled_savepoint
      close_owned_browser
      port = available_port
      args = [
        "--remote-debugging-port=#{port}",
        "--user-data-dir=#{@profile.profile_dir('jotter')}",
        "--no-first-run",
        "--no-default-browser-check",
        @savepoint_url
      ]
      @chrome_pid = Process.spawn(@profile.chrome_path, *args, out: File::NULL, err: File::NULL)
      wait_for_debugger(port)
      status("Jotter: 素のChromeで#{@savepoint_settle_seconds}秒間、暗号処理を待機")
      @sleeper.call(@savepoint_settle_seconds)

      require "ferrum"
      @browser = Ferrum::Browser.new(
        url: "http://127.0.0.1:#{port}",
        timeout: @timeout,
        process_timeout: 60,
        pending_connection_errors: false)
      @page = select_jotter_page
      @page.on(:dialog) { |dialog| dialog.accept }
      status("Jotter: 暗号処理後のChromeへ自動操作を接続")
    rescue StandardError
      close_owned_browser
      raise
    end

    def available_port
      server = TCPServer.new("127.0.0.1", 0)
      server.addr[1]
    ensure
      server&.close
    end

    def select_jotter_page
      pages = @browser.pages
      page = pages.reverse.find do |candidate|
        uri = URI(candidate.current_url)
        uri.host == "jotter.me"
      rescue StandardError
        false
      end
      raise "Jotter用Chromeにjotter.meのタブが見つかりません" unless page

      status("Jotter: 開いている#{pages.size}タブからJotterタブを選択")
      page
    end

    def wait_for_debugger(port)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
      uri = URI("http://127.0.0.1:#{port}/json/version")
      loop do
        begin
          response = Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 1) do |http|
            http.get(uri.request_uri)
          end
          return true if response.is_a?(Net::HTTPSuccess)
        rescue StandardError
          # Chromeのデバッグポート起動待ち。
        end
        raise "Jotter用Chromeの起動を確認できません" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        @sleeper.call(0.2)
      end
    end

    def close_owned_browser
      return unless @owns_browser

      if @browser
        @browser.close if @chrome_pid
        @browser.quit
      end
    rescue StandardError
      nil
    ensure
      @page = nil
      @browser = nil
      reap_chrome_process
    end

    def reap_chrome_process
      return unless @chrome_pid

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      loop do
        waited = Process.waitpid(@chrome_pid, Process::WNOHANG)
        return if waited
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        @sleeper.call(0.1)
      end
      Process.kill("TERM", @chrome_pid)
      Process.waitpid(@chrome_pid) rescue nil
    rescue Errno::ECHILD, Errno::ESRCH, Errno::EINVAL
      nil
    ensure
      @chrome_pid = nil
    end

    def safe_evaluate(script, *args)
      browser.evaluate(script, *args)
    rescue StandardError
      # SPA遷移中は実行コンテキストが破棄されるか、CDP応答が時間切れになる。
      nil
    end

    def safe_at_css(selector)
      browser.at_css(selector)
    rescue StandardError
      nil
    end

    def safe_at_xpath(selector)
      browser.at_xpath(selector)
    rescue StandardError
      nil
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
      return @page if @page
      return @browser if @browser

      @browser = begin
        require "ferrum"
        Ferrum::Browser.new(
          browser_path: @profile.chrome_path,
          browser_options: { "user-data-dir" => @profile.profile_dir("jotter") },
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
