require "digest"
require "fileutils"
require "net/http"
require "open-uri"
require "tmpdir"
require "uri"
require_relative "blogger_image_browser"
require_relative "token_store"

module SnsMultipost
  class BloggerImageStore
    SCRATCH_TITLE = "sns-multipost 画像アップロード作業用（公開しない）".freeze
    DEFAULT_CACHE_PATH = File.expand_path("../state/blogger_image_store.json", __dir__)

    DEFAULT_FETCHER = ->(url) { URI.open(url, "rb", &:read) }
    DEFAULT_VALIDATOR = lambda do |url|
      uri = URI(url)
      request = Net::HTTP::Head.new(uri.request_uri)
      response = Net::HTTP.start(
        uri.host, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: 10, read_timeout: 20) { |http| http.request(request) }
      type = response["Content-Type"].to_s
      response.code.to_i.between?(200, 299) && type.start_with?("image/")
    end

    def initialize(api:, browser:, store: TokenStore.new(DEFAULT_CACHE_PATH),
                   fetcher: DEFAULT_FETCHER, validator: DEFAULT_VALIDATOR)
      @api = api
      @browser = browser
      @store = store
      @fetcher = fetcher
      @validator = validator
    end

    def urls_for(media_paths:, media_urls:, failure_screenshot_path: nil)
      paths = Array(media_paths)
      sources = Array(media_urls)
      count = [paths.length, sources.length].max
      return [] if count.zero?

      data = load_data
      cleanup_pending!(data)
      records = count.times.map do |index|
        { index: index, path: paths[index], source_url: sources[index] }
      end
      results = Array.new(count)
      unresolved = []

      records.each do |record|
        cached = cached_url(data, record)
        if cached
          results[record[:index]] = cached
        else
          unresolved << record
        end
      end
      return results.compact if unresolved.empty?

      Dir.mktmpdir("sns-multipost-blogger") do |dir|
        unresolved.each { |record| materialize!(record, dir) }
        upload_records!(
          unresolved, results, data,
          failure_screenshot_path: failure_screenshot_path)
      end
      results.compact
    end

    private

    def load_data
      raw = @store.load
      {
        "images" => raw["images"].is_a?(Hash) ? raw["images"] : {},
        "pending_drafts" => Array(raw["pending_drafts"]).map(&:to_s).uniq
      }
    end

    def save_data(data)
      @store.save(data)
    end

    def cached_url(data, record)
      images = data["images"]
      source = record[:source_url].to_s
      return images["source:#{source}"] unless source.empty? || images["source:#{source}"].to_s.empty?

      path = record[:path].to_s
      return nil unless File.file?(path)
      images["sha256:#{Digest::SHA256.file(path).hexdigest}"]
    end

    def materialize!(record, dir)
      path = record[:path].to_s
      return if File.file?(path)

      source = record[:source_url].to_s
      raise "Bloggerへ渡す画像ファイルまたは画像URLがありません" if source.empty?
      uri = URI(source)
      extension = File.extname(uri.path)
      extension = ".bin" if extension.empty?
      path = File.join(dir, format("%02d%s", record[:index] + 1, extension))
      File.binwrite(path, @fetcher.call(source))
      record[:path] = path
    end

    def upload_records!(records, results, data, failure_screenshot_path:)
      draft = @api.insert_post(title: SCRATCH_TITLE, html: "", is_draft: true)
      draft_id = draft["id"].to_s
      raise "Bloggerの画像アップロード用下書きIDを取得できません" if draft_id.empty?
      data["pending_drafts"] << draft_id
      data["pending_drafts"].uniq!
      save_data(data)

      error = nil
      begin
        by_path = records.to_h { |record| [File.expand_path(record[:path]), record] }
        @browser.upload(
          draft_id: draft_id,
          media_paths: records.map { |record| record[:path] },
          failure_screenshot_path: failure_screenshot_path) do |path, url|
          record = by_path.fetch(File.expand_path(path))
          validate_url!(url)
          remember!(data, record, url)
          results[record[:index]] = url
          save_data(data)
        end
      rescue StandardError => e
        error = e
      ensure
        begin
          @api.delete_post(draft_id)
          data["pending_drafts"].delete(draft_id)
          save_data(data)
        rescue StandardError => cleanup_error
          error ||= cleanup_error
        end
      end
      raise error if error
      missing = records.reject { |record| results[record[:index]] }
      raise "Blogger画像URLを取得できないファイルがあります" unless missing.empty?
    end

    def remember!(data, record, url)
      digest = Digest::SHA256.file(record[:path]).hexdigest
      data["images"]["sha256:#{digest}"] = url
      source = record[:source_url].to_s
      data["images"]["source:#{source}"] = url unless source.empty?
    end

    def validate_url!(url)
      uri = URI(url)
      unless uri.scheme == "https" && uri.host == "blogger.googleusercontent.com" && @validator.call(url)
        raise "Blogger画像の公開URLを確認できません: #{url}"
      end
    rescue URI::InvalidURIError
      raise "Blogger画像URLが不正です: #{url}"
    end

    def cleanup_pending!(data)
      data["pending_drafts"].dup.each do |draft_id|
        @api.delete_post(draft_id)
        data["pending_drafts"].delete(draft_id)
        save_data(data)
      end
    end
  end
end
