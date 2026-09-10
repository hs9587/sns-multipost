require "fileutils"
require_relative "browser_profile"

module SnsMultipost
  class BloggerImageBrowser
    EDIT_URL = "https://www.blogger.com/blog/post/edit".freeze
    IMAGE_BUTTON_SELECTOR = '[aria-label="画像を挿入"]'.freeze
    UPLOAD_OPTION_XPATH = "//*[@aria-label='パソコンからアップロード' and @role='menuitem']".freeze
    PICKER_INSERT_XPATH = <<~'XPATH'.strip.freeze
      //*[self::button or @role='button'][
        starts-with(normalize-space(.), '選択') or
        starts-with(normalize-space(.), '挿入') or
        starts-with(normalize-space(.), 'Select') or
        starts-with(normalize-space(.), 'Insert') or
        starts-with(@aria-label, '選択') or starts-with(@aria-label, '挿入') or
        starts-with(@aria-label, 'Select') or starts-with(@aria-label, 'Insert')
      ]
    XPATH

    IMAGE_URLS_JS = <<~'JS'.freeze
      Array.from(document.images)
        .map((image) => image.currentSrc || image.src)
        .filter((url) => url.startsWith('https://blogger.googleusercontent.com/'))
    JS

    def self.original_url(display_url)
      value = display_url.to_s
      return value unless value.start_with?("https://blogger.googleusercontent.com/")
      value.sub(%r{/s\d+/}, "/s0/")
    end

    def initialize(blog_id:, browser: nil, profile: BrowserProfile.new,
                   headless: false, timeout: 30, upload_timeout: 60,
                   upload_settle_seconds: 5,
                   sleeper: ->(seconds) { sleep seconds })
      @blog_id = blog_id.to_s
      @browser = browser
      @profile = profile
      @headless = headless
      @timeout = timeout
      @upload_timeout = upload_timeout
      @upload_settle_seconds = upload_settle_seconds
      @sleeper = sleeper
      @owns_browser = browser.nil?
    end

    def upload(draft_id:, media_paths:, failure_screenshot_path: nil)
      paths = Array(media_paths)
      return [] if paths.empty?

      browser.goto("#{EDIT_URL}/#{@blog_id}/#{draft_id}")
      wait_for { visible_css(IMAGE_BUTTON_SELECTOR) } ||
        raise("Bloggerの画像を挿入ボタンが見つかりません。専用Chromeのログイン状態を確認してください")

      known = image_urls
      uploaded = paths.map do |path|
        url = upload_one(path, known)
        known << url
        original = self.class.original_url(url)
        yield(path, original) if block_given?
        original
      end
      @sleeper.call(5)
      uploaded
    rescue StandardError
      capture_failure_screenshot(failure_screenshot_path)
      capture_failure_diagnostics(failure_screenshot_path)
      raise
    ensure
      browser.quit if @owns_browser && @browser
    end

    private

    def upload_one(path, known)
      button = wait_for { visible_css(IMAGE_BUTTON_SELECTOR) }
      raise "Bloggerの画像を挿入ボタンが見つかりません" unless button
      button.evaluate("this.click()")

      option = wait_for { visible_xpath(UPLOAD_OPTION_XPATH) }
      raise "Bloggerのパソコンからアップロード項目が見つかりません" unless option
      picker = open_picker(option)
      raise "Google画像追加画面を確認できません" unless picker
      input = wait_for { picker.at_css('input[type="file"]') rescue nil }
      raise "Google画像追加画面のファイル入力が見つかりません" unless input
      input.select_file(path)

      # Google画像追加画面の内部URLやDOMは変動するため、特定のプレビュー
      # 要素には依存しない。select_file後に入力要素自体が差し替わるため
      # filesの再読込も行わない。アップロードの静定時間を置き、
      # 使用可能になった確定ボタンを押す。
      @sleeper.call(@upload_settle_seconds)
      # ファイル選択に伴うナビゲーションでURLやexecution contextが更新される。
      # docs.google.comという初期URLには依存せず、現在有効な全フレームから探す。
      insert = wait_for(timeout: @upload_timeout) { picker_insert_button_from_frames }
      raise "Google画像追加画面の選択／挿入ボタンを押せません: #{path}" unless insert
      begin
        insert.evaluate("this.click()")
      rescue StandardError => e
        # クリックでGoogle画像追加フレームが閉じると、CDPの応答より先に
        # execution contextが破棄されることがある。クリック後の正常な遷移
        # として本文側の画像出現を待つ。
        raise unless no_execution_context_error?(e)
      end

      added = wait_for(timeout: @upload_timeout) { (image_urls - known).first }
      raise "Blogger本文への画像挿入を確認できません: #{path}" unless added
      added
    end

    # Ferrum's coordinate click can occasionally miss this floating menu item.
    # A DOM click is reliable here; the physical click remains as a fallback for
    # a future Blogger UI that ignores synthetic clicks.
    def open_picker(option)
      option.evaluate("this.click()")
      picker = wait_for { picker_frame }
      return picker if picker

      option = visible_xpath(UPLOAD_OPTION_XPATH)
      return nil unless option
      option.click
      wait_for { picker_frame }
    end

    def image_urls
      browser.frames.flat_map do |frame|
        next [] if frame.url.to_s.start_with?("https://docs.google.com/")
        next [] unless frame.execution_id
        frame.evaluate(IMAGE_URLS_JS)
      rescue StandardError
        # Google画像追加フレームは「選択／挿入」の直後に破棄される。
        # browser.frames に一瞬残った無効なフレームのurlやcontextを
        # 参照できなくても、ほかの本文フレームの確認を続ける。
        []
      end.uniq
    rescue StandardError
      []
    end

    def picker_insert_button(picker)
      picker.xpath(PICKER_INSERT_XPATH).find do |node|
        node.evaluate(<<~'JS')
          this.getClientRects().length > 0 && !this.disabled &&
            this.getAttribute('aria-disabled') !== 'true'
        JS
      rescue Ferrum::Error
        false
      end
    rescue Ferrum::Error
      nil
    end

    def picker_insert_button_from_frames
      current_frames.each do |frame|
        button = picker_insert_button(frame)
        return button if button
      end
      nil
    end

    def current_frames
      browser.frames.sort_by do |frame|
        frame.url.to_s.start_with?("https://docs.google.com/") ? 0 : 1
      rescue StandardError
        2
      end
    rescue StandardError
      []
    end

    def no_execution_context_error?(error)
      error.class.name.end_with?("NoExecutionContextError")
    end

    def picker_frame
      tree = browser.page.command("Page.getFrameTree").fetch("frameTree")
      info = flatten_frames(tree).find do |frame|
        frame.fetch("url", "").start_with?("https://docs.google.com/")
      end
      frame = info && browser.frame_by(id: info.fetch("id"))
      frame if frame&.execution_id
    rescue Ferrum::Error
      nil
    end

    def flatten_frames(node)
      [node.fetch("frame")] +
        node.fetch("childFrames", []).flat_map { |child| flatten_frames(child) }
    end

    def visible_css(selector)
      browser.css(selector).find do |node|
        node.evaluate("this.getClientRects().length > 0")
      rescue Ferrum::Error
        false
      end
    end

    def visible_xpath(selector)
      browser.xpath(selector).find do |node|
        node.evaluate("this.getClientRects().length > 0")
      rescue Ferrum::Error
        false
      end
    end

    def capture_failure_screenshot(path)
      return false if path.to_s.empty? || !@browser
      FileUtils.mkdir_p(File.dirname(path))
      browser.screenshot(path: path, full: false)
      true
    rescue StandardError
      false
    end

    def capture_failure_diagnostics(path)
      return false if path.to_s.empty? || !@browser

      lines = current_frames.each_with_index.map do |frame, index|
        buttons = frame.xpath("//*[self::button or @role='button']").filter_map do |node|
          node.evaluate(<<~'JS')
            (() => {
              if (this.getClientRects().length === 0) return null;
              const text = (this.innerText || this.textContent || '').trim().replace(/\s+/g, ' ');
              const aria = (this.getAttribute('aria-label') || '').trim();
              return {text: text.slice(0, 80), aria: aria.slice(0, 80),
                      disabled: !!this.disabled,
                      ariaDisabled: this.getAttribute('aria-disabled')};
            })()
          JS
        rescue StandardError
          nil
        end.first(20)
        "frame[#{index}] #{diagnostic_url(frame)} buttons=#{buttons.inspect}"
      rescue StandardError => e
        "frame[#{index}] unreadable=#{e.class}"
      end
      File.write(path.sub(/\.png\z/i, ".txt"), lines.join("\n") + "\n")
      true
    rescue StandardError
      false
    end

    def diagnostic_url(frame)
      require "uri"
      uri = URI(frame.url.to_s)
      return "(empty)" if uri.host.to_s.empty?

      "#{uri.scheme}://#{uri.host}#{uri.path}"
    rescue StandardError
      "(unreadable)"
    end

    def browser
      @browser ||= begin
        require "ferrum"
        Ferrum::Browser.new(
          browser_path: @profile.chrome_path,
          browser_options: { "user-data-dir" => @profile.profile_dir("blogger") },
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
