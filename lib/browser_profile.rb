require "fileutils"

module SnsMultipost
  class BrowserProfile
    SERVICE_URLS = {
      "mixi2" => "https://mixi.social/home"
    }.freeze

    WINDOWS_CHROME_PATHS = [
      "C:/Program Files/Google/Chrome/Application/chrome.exe",
      "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe"
    ].freeze

    def initialize(root: File.expand_path("..", __dir__), chrome_path: nil)
      @root = root
      @chrome_path = chrome_path
    end

    def command(service)
      url = SERVICE_URLS.fetch(service) { raise ArgumentError, "未対応のSNSです: #{service}" }
      profile = File.join(@root, "state", "browser", service)
      FileUtils.mkdir_p(profile)
      [resolved_chrome_path,
       "--user-data-dir=#{profile}",
       "--no-first-run",
       "--no-default-browser-check",
       url]
    end

    def launch(service)
      Process.spawn(*command(service))
    end

    def profile_dir(service)
      File.join(@root, "state", "browser", service)
    end

    private

    def resolved_chrome_path
      explicit = @chrome_path.to_s.strip
      explicit = ENV["SNS_MULTIPOST_CHROME_PATH"].to_s.strip if explicit.empty?
      return explicit if !explicit.empty? && File.file?(explicit)

      found = WINDOWS_CHROME_PATHS.find { |path| File.file?(path) }
      return found if found

      raise "Google Chromeが見つかりません。SNS_MULTIPOST_CHROME_PATHを設定してください"
    end
  end
end
