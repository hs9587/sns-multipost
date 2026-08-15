require "fileutils"
require "digest"
require "net/http"
require "socket"
require "uri"
require_relative "browser_profile"

module SnsMultipost
  class JotterBrowser
    HOME_URL = "https://jotter.me/ja-JP/".freeze
    WALLET_URL = "https://jotter.me/ja-JP/wallet/".freeze
    TEXT_SELECTOR = 'textarea[name="text"]'.freeze
    MEDIA_SELECTOR = 'input[type="file"]'.freeze
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

    HOME_RESET_JS = <<~'JS'.freeze
      (() => {
        history.replaceState(null, '', '/ja-JP/');
        location.reload();
        return true;
      })()
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

    WALLET_STATE_JS = <<~'JS'.freeze
      (() => {
        const normalize = (value) => (value || '').replace(/\s+/g, ' ').trim();
        const lines = (document.body?.innerText || '')
          .split(/\r?\n/).map(normalize).filter(Boolean);
        const definitions = {
          accountId: ['口座ID', '口座 ID', 'Account ID'],
          browserId: ['Browser ID', 'ブラウザID', 'ブラウザ ID'],
          available: ['利用可能', 'Available'],
          unverified: ['未検証', 'Unverified'],
          needsUpdate: ['要更新', 'Needs update', 'Update required'],
          scheduled: ['入金予定', 'Scheduled income', 'Scheduled deposit'],
          total: ['合計', 'Total']
        };
        const allLabels = Object.values(definitions).flat();
        const isLabel = (line) => allLabels.some((label) => line === label);
        const valueAfter = (labels) => {
          for (let index = 0; index < lines.length; index += 1) {
            const line = lines[index];
            const label = labels.find((candidate) =>
              line === candidate || line.startsWith(`${candidate}:`) ||
              line.startsWith(`${candidate}：`) || line.startsWith(`${candidate} `));
            if (!label) continue;
            const inline = normalize(line.slice(label.length).replace(/^\s*[:：]\s*/, ''));
            if (inline) return inline;
            for (let offset = 1; offset <= 3; offset += 1) {
              const candidate = lines[index + offset];
              if (!candidate || isLabel(candidate)) continue;
              return candidate;
            }
          }
          return null;
        };
        const numberFrom = (value) => {
          const match = normalize(value).match(/-?[0-9][0-9,.]*/);
          return match ? match[0] : null;
        };
        const relevant = [];
        lines.forEach((line, index) => {
          if (!allLabels.some((label) => line.includes(label))) return;
          for (let offset = 0; offset <= 2; offset += 1) {
            const candidate = lines[index + offset];
            if (candidate && !relevant.includes(candidate)) relevant.push(candidate);
          }
        });
        const mask = (value) => value
          .replace(/[A-Za-z0-9+_\/=.-]{12,}/g, '<id>')
          .replace(/[0-9a-f]{12,}/gi, '<id>');
        const accountId = valueAfter(definitions.accountId);
        const browserId = valueAfter(definitions.browserId);
        return {
          wallet: location.pathname.includes('/wallet/') ||
            lines.some((line) => line.includes('支払いと送金') ||
              line.includes('Payment and transfer')),
          accountId,
          browserId,
          balances: {
            available: numberFrom(valueAfter(definitions.available)),
            unverified: numberFrom(valueAfter(definitions.unverified)),
            needsUpdate: numberFrom(valueAfter(definitions.needsUpdate)),
            scheduled: numberFrom(valueAfter(definitions.scheduled)),
            total: numberFrom(valueAfter(definitions.total))
          },
          diagnostic: relevant.slice(0, 30).map(mask)
        };
      })()
    JS

    MEDIA_STATE_JS = <<~'JS'.freeze
      (() => {
        const normalize = (value) => (value || '').replace(/\s+/g, ' ').trim();
        const editor = document.querySelector('textarea[name="text"]');
        const root = editor?.closest('form') || editor?.parentElement?.parentElement || document;
        let inputs = Array.from(root.querySelectorAll('input[type="file"]'));
        if (inputs.length === 0) inputs = Array.from(document.querySelectorAll('input[type="file"]'));
        const imageInput = inputs.find((input) =>
          (input.accept || '').toLowerCase().includes('image')) || inputs[0] || null;
        const images = Array.from(root.querySelectorAll('img'))
          .filter((image) => !image.classList.contains('user-face') &&
            (image.currentSrc || image.src));
        const lines = (document.body?.innerText || '')
          .split(/\r?\n/).map(normalize).filter(Boolean);
        const denLines = lines.filter((line) =>
          /(?:[0-9][0-9,.]*\s*DEN|DEN\s*[0-9][0-9,.]*)/i.test(line));
        const statusLines = lines.filter((line) =>
          /添付ファイル|メディア|準備中|読み込み完了|保存中|attachment|media|prepar|loading/i.test(line));
        const mask = (value) => value
          .replace(/[A-Za-z0-9+_\/=.-]{12,}/g, '<id>')
          .replace(/[0-9a-f]{12,}/gi, '<id>');
        return {
          hasInput: !!imageInput,
          inputCount: inputs.length,
          accept: imageInput?.accept || '',
          multiple: !!imageInput?.multiple,
          fileCount: imageInput?.files?.length || 0,
          previewCount: images.length,
          requiredDen: (() => {
            const total = denLines.find((line) => /total\s*cost|合計|総額/i.test(line));
            const source = total || (denLines.length === 1 ? denLines[0] : null);
            const match = source && source.match(/(?:([0-9][0-9,.]*)\s*DEN|DEN\s*([0-9][0-9,.]*))/i);
            return match ? (match[1] || match[2]) : null;
          })(),
          denLines: Array.from(new Set(denLines)).slice(0, 10),
          statusLines: Array.from(new Set(statusLines)).slice(0, 10).map(mask)
        };
      })()
    JS

    VERIFY_UNVERIFIED_JS = <<~'JS'.freeze
      (() => {
        const normalize = (value) => (value || '').replace(/\s+/g, ' ').trim();
        const labels = ['未検証', 'Unverified'];
        const visible = (node) => !!(node.offsetWidth || node.offsetHeight || node.getClientRects().length);
        const interactive = Array.from(document.querySelectorAll(
          'button, a, [role="button"], summary, input[type="button"], input[type="submit"]'));
        let target = interactive.find((node) => visible(node) &&
          labels.includes(normalize(node.innerText || node.value || node.textContent)));
        if (!target) {
          const label = Array.from(document.querySelectorAll('span, div, dt, th, p'))
            .find((node) => visible(node) && labels.includes(normalize(node.textContent)));
          // Jotterのウォレット行はbutton/linkとは限らず、親要素の
          // click handlerが子要素からのbubblingを受け取る構造がある。
          // 文字要素そのものをクリックすれば、その構造でも作動する。
          target = label?.closest('button, a, [role="button"], summary') || label;
        }
        if (!target) return false;
        target.click();
        return true;
      })()
    JS

    def initialize(savepoint_url:, account_name: nil, browser: nil,
                   profile: BrowserProfile.new, headless: false, timeout: 20,
                   auth_timeout: AUTH_TIMEOUT, confirmation_timeout: 40,
                   wallet_browser_id_timeout: 60,
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
      @wallet_browser_id_timeout = wallet_browser_id_timeout
      @savepoint_settle_seconds = savepoint_settle_seconds
      @logger = logger
      @sleeper = sleeper
      @owns_browser = browser.nil?
      raise "Jotterのsavepoint_urlが未設定です" if @savepoint_url.empty?
    end

    def smoke
      open_authenticated_home
      raise "Jotterの投稿フォームを開けません" unless wait_for(timeout: @auth_timeout) {
        safe_evaluate(OPEN_COMPOSER_JS)
      }
      editor = wait_for { safe_at_css(TEXT_SELECTOR) }
      submit = wait_for { safe_at_css(SUBMIT_SELECTOR) }
      public_option = safe_evaluate(SET_PUBLIC_JS)
      { "hasEditor" => !!editor, "hasSubmit" => !!submit, "hasPublic" => !!public_option }
    ensure
      close_owned_browser
    end

    def wallet_smoke
      open_wallet_state
    ensure
      close_owned_browser
    end

    def wallet_hold
      state = open_wallet_state
      yield state if block_given?
      @sleeper.call(2)
      safe_evaluate(WALLET_STATE_JS) || state
    ensure
      close_owned_browser
    end

    def wallet_verify(required_den: 90, attempts: 3, verification_timeout: 180)
      state = open_wallet_state
      yield state if block_given?
      verify_wallet_den(state, required_den: required_den, attempts: attempts,
                        verification_timeout: verification_timeout)
    ensure
      close_owned_browser
    end

    def media_smoke(path)
      absolute = File.expand_path(path.to_s)
      raise "Jotter画像ファイルが見つかりません: #{path}" unless File.file?(absolute)

      open_authenticated_home
      raise "Jotterの投稿フォームを開けません" unless wait_for(timeout: @auth_timeout) {
        safe_evaluate(OPEN_COMPOSER_JS)
      }
      wait_for { safe_at_css(TEXT_SELECTOR) } ||
        raise("Jotterの本文入力欄が見つかりません")
      raise "Jotterの公開範囲を「公開」にできません" unless safe_evaluate(SET_PUBLIC_JS)

      before = safe_evaluate(MEDIA_STATE_JS) || {}
      input = wait_for do
        safe_at_css('input[type="file"][accept*="image"]') || safe_at_css(MEDIA_SELECTOR)
      end
      raise "Jotterの画像入力欄が見つかりません" unless input
      input.select_file(absolute)

      attached = wait_for(timeout: [@auth_timeout, 60].max) do
        state = safe_evaluate(MEDIA_STATE_JS)
        state if state && (state["fileCount"].to_i.positive? ||
          state["previewCount"].to_i > before["previewCount"].to_i)
      end
      raise "Jotterの画像選択を確認できません: #{absolute}" unless attached

      @sleeper.call(3)
      safe_evaluate(MEDIA_STATE_JS) || attached
    ensure
      close_owned_browser
    end

    def post(text:, media_paths: [], expected_browser_id_fingerprint: nil,
             failure_screenshot_path: nil)
      paths = Array(media_paths).first(1)
      wallet = nil
      unless paths.empty?
        wallet = open_wallet_state(require_browser_id: false)
        verify_wallet_identity!(wallet, expected_browser_id_fingerprint)
        wallet = verify_wallet_den(wallet, required_den: 90).fetch("after")
      else
        open_authenticated_home
      end

      return_to_home || raise("Jotterのホーム画面を確認できません")
      existing_urls = safe_evaluate(POST_URLS_JS) || []
      raise "Jotterの投稿フォームを開けません" unless wait_for(timeout: @auth_timeout) {
        safe_evaluate(OPEN_COMPOSER_JS)
      }

      editor = wait_for { safe_at_css(TEXT_SELECTOR) }
      raise "Jotterの本文入力欄が見つかりません" unless editor
      editor.click.type(text)
      raise "Jotterの公開範囲を「公開」にできません" unless safe_evaluate(SET_PUBLIC_JS)

      unless paths.empty?
        media_state = attach_media(paths.first)
        required_den = den_number(media_state["requiredDen"])
        raise "Jotterの画像投稿に必要なDENを確認できません" unless required_den.positive?

        available = den_number(wallet.dig("balances", "available"))
        if available < required_den
          raise "Jotter画像投稿には#{required_den} DEN必要ですが、利用可能DENは#{available}です。" \
                "jotter_wallet_holdで振替後、jotter_wallet_verifyを実行してください"
        end
        status("Jotter: 画像1枚 必要DEN=#{required_den} 利用可能DEN=#{available}")
      end

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

    def den_number(value)
      value.to_s.delete(",").to_i
    end

    def wallet_fingerprint(value)
      text = value.to_s.strip
      return nil if text.empty?

      Digest::SHA256.hexdigest("jotter-wallet-v1\0#{text}")[0, 12]
    end

    def verify_wallet_identity!(state, expected)
      expected = expected.to_s.strip
      raise "Jotter Browser IDの保存済み基準がありません。jotter_wallet_smokeを実行してください" if expected.empty?

      current = wallet_fingerprint(state["browserId"])
      unless current
        status("Jotter: Browser IDは画面に未表示（確認済み専用プロファイルを継続使用）")
        return
      end
      raise "Jotter Browser IDが保存済み基準と一致しません" unless current == expected

      status("Jotter: Browser ID一致（fingerprint=#{current}）")
    end

    def verify_wallet_den(state, required_den:, attempts: 3, verification_timeout: 180)
      available = den_number(state.dig("balances", "available"))
      return { "status" => "already_available", "attempts" => 0,
               "before" => state, "after" => state } if available >= required_den

      unverified = den_number(state.dig("balances", "unverified"))
      if available + unverified < required_den
        raise "JotterのDENが不足しています（必要#{required_den}、利用可能#{available}、未検証#{unverified}）"
      end

      before = state
      attempts.times do |index|
        status("Jotter: 未検証DENの検証要求 #{index + 1}/#{attempts}")
        raise "Jotterの未検証DENを押せません" unless safe_evaluate(VERIFY_UNVERIFIED_JS)

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        next_report = 30
        loop do
          @sleeper.call(5)
          candidate = safe_evaluate(WALLET_STATE_JS)
          if candidate
            state = candidate
            available = den_number(state.dig("balances", "available"))
            if available >= required_den
              return { "status" => "available", "attempts" => index + 1,
                       "before" => before, "after" => state }
            end
          end
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          if elapsed >= next_report
            status("Jotter: DEN検証待ち #{elapsed.to_i}/#{verification_timeout}秒 " \
                   "利用可能=#{available}")
            next_report += 30
          end
          break if elapsed >= verification_timeout
        end
      end
      raise "Jotterの利用可能DENが#{required_den}以上になりませんでした（現在#{available}）"
    end

    def attach_media(path)
      absolute = File.expand_path(path.to_s)
      raise "Jotter画像ファイルが見つかりません: #{path}" unless File.file?(absolute)

      before = safe_evaluate(MEDIA_STATE_JS) || {}
      input = wait_for do
        safe_at_css('input[type="file"][accept*="image"]') || safe_at_css(MEDIA_SELECTOR)
      end
      raise "Jotterの画像入力欄が見つかりません" unless input

      input.select_file(absolute)
      attached = wait_for(timeout: [@auth_timeout, 60].max) do
        candidate = safe_evaluate(MEDIA_STATE_JS)
        candidate if candidate && (candidate["fileCount"].to_i.positive? ||
          candidate["previewCount"].to_i > before["previewCount"].to_i)
      end
      raise "Jotterの画像選択を確認できません: #{absolute}" unless attached

      @sleeper.call(3)
      safe_evaluate(MEDIA_STATE_JS) || attached
    end

    def open_wallet_state(require_browser_id: true)
      open_authenticated_home
      goto_safely(WALLET_URL)
      last_state = nil
      ready = wait_for(timeout: @auth_timeout) do
        last_state = safe_evaluate(WALLET_STATE_JS)
        last_state && last_state["wallet"]
      end
      raise "Jotterのウォレット画面を確認できません" unless ready

      # Wallet values and the peer-dependent Browser ID may appear after the
      # route itself becomes visible.
      @sleeper.call(2)
      state = safe_evaluate(WALLET_STATE_JS) || last_state
      if require_browser_id && !state["browserId"]
        status("Jotter: Browser ID表示を最大#{@wallet_browser_id_timeout}秒待機")
        observed = wait_for(timeout: @wallet_browser_id_timeout) do
          candidate = safe_evaluate(WALLET_STATE_JS)
          candidate if candidate && candidate["browserId"]
        end
        state = observed if observed
      end
      state
    end

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

        home_ready = return_to_home
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

    def return_to_home
      goto_safely(HOME_URL)
      ready = wait_for(timeout: [@auth_timeout, 10].min) do
        state = safe_evaluate(LOGGED_IN_JS)
        state && state["loggedIn"]
      end
      return true if ready

      status("Jotter: 本人確認画面を閉じるためホームを再読込")
      safe_evaluate(HOME_RESET_JS)
      wait_for(timeout: @auth_timeout) do
        state = safe_evaluate(LOGGED_IN_JS)
        state && state["loggedIn"]
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
      pages = []
      page = wait_for(timeout: 15) do
        pages = @browser.pages
        find_jotter_page(pages)
      end
      unless page
        status("Jotter: 起動時のJotterタブが見つからないためセーブポイントを再表示")
        recovery_page = pages.reverse.first || @browser.pages.reverse.first
        raise "Jotter用Chromeに操作可能なタブが見つかりません" unless recovery_page

        @page = recovery_page
        goto_safely(@savepoint_url)
        status("Jotter: 再表示後#{@savepoint_settle_seconds}秒間、暗号処理を待機")
        @sleeper.call(@savepoint_settle_seconds)
        pages = @browser.pages
        page = wait_for(timeout: 15) do
          pages = @browser.pages
          find_jotter_page(pages)
        end
      end
      raise "Jotter用Chromeにjotter.meのタブが見つかりません" unless page

      status("Jotter: 開いている#{pages.size}タブからJotterタブを選択")
      page
    end

    def find_jotter_page(pages)
      pages.reverse.find do |candidate|
        uri = URI(candidate.current_url)
        uri.host == "jotter.me"
      rescue StandardError
        false
      end
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
