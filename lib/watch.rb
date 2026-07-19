require "time"
require "fileutils"
require_relative "job_queue"
require_relative "media"
require_relative "html_text"

module SnsMultipost
  class Watch
    def initialize(config:, api:, queue:, titles:, self_posted:,
                   state_path:, media_root:, media_fetcher: nil)
      @config = config
      @api = api
      @queue = queue
      @titles = titles
      @self_posted = self_posted
      @state_path = state_path
      @media_root = media_root
      @media_fetcher = media_fetcher
    end

    def run(now: Time.now)
      since = File.exist?(@state_path) ? File.read(@state_path).strip : nil
      statuses = @api.statuses(
        account_id: @config["fedibird"]["account_id"], since_id: since)
      if since.nil?
        # 初回は現在位置の記録のみ（過去分をまとめて配信しない）
        record_state(statuses)
        return 0
      end
      statuses.reverse_each do |st|
        next if st["reblog"] || st["in_reply_to_id"]
        next if @self_posted.include?(st["id"])
        enqueue_status(st, now: now)
      end
      record_state(statuses)
      statuses.size
    end

    private

    def record_state(statuses)
      newest = statuses.first
      return unless newest
      FileUtils.mkdir_p(File.dirname(@state_path))
      File.write(@state_path, newest["id"].to_s)
    end

    def enqueue_status(st, now:)
      text = HtmlText.to_text(st["content"].to_s)
      return if text.empty?
      title = @titles.title_for(text)
      urls = (st["media_attachments"] || []).map { |m| m["url"] }
      media_paths =
        if urls.empty?
          []
        else
          opts = @media_fetcher ? { fetcher: @media_fetcher } : {}
          Media.download(urls, File.join(@media_root, st["id"].to_s), **opts)
        end
      @config.targets_for(:watch).each do |sns|
        @queue.enqueue(
          Job.new(sns: sns, text: text, title: title, media_paths: media_paths,
                  source_url: st["url"], created_at: now.iso8601),
          now: now)
      end
    end
  end
end
