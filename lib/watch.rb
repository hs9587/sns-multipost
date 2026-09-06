require "time"
require "fileutils"
require "json"
require "securerandom"
require_relative "job_queue"
require_relative "media"
require_relative "html_text"
require_relative "atomic_file"

module SnsMultipost
  class Watch
    def initialize(config:, api:, queue:, titles:, self_posted:,
                   state_path:, media_root:, media_fetcher: nil, batch_path: nil)
      @config = config
      @api = api
      @queue = queue
      @titles = titles
      @self_posted = self_posted
      @state_path = state_path
      @media_root = media_root
      @media_fetcher = media_fetcher
      @batch_path = batch_path || File.join(File.dirname(state_path), "watch_batch.json")
    end

    # enqueue: false（基準合わせ / --sync-only）は、新着をキューに積まず
    # since_id だけを最新へ前進させる。常駐 run_queue とのレースやメディアの
    # 無駄ダウンロードを避けつつ「今の新着は流さず基準だけ今に合わせる」。
    def run(now: Time.now, enqueue: true)
      since = File.exist?(@state_path) ? File.read(@state_path).strip : nil
      discard_completed_batch(since) if since
      statuses = @api.statuses(
        account_id: @config["fedibird"]["account_id"], since_id: since)
      if since.nil?
        # 初回は現在位置の記録のみ（過去分をまとめて配信しない）
        record_state(statuses)
        return 0
      end
      if enqueue && statuses.any?
        batch_id = prepare_batch(since, statuses)
        statuses.reverse_each do |st|
          next if st["reblog"] || st["in_reply_to_id"]
          next if @self_posted.include?(st["id"])
          enqueue_status(st, now: now, batch_id: batch_id)
        end
      end
      record_state(statuses)
      finish_batch if !enqueue || statuses.any?
      enqueue ? statuses.size : 0
    end

    # 監視基準を古い投稿IDへ戻し、次回の通常runで直近の投稿を再検出できるようにする。
    # この操作自体はキュー作成・画像取得を行わない。
    def rewind(count: 1)
      count = Integer(count)
      raise "巻き戻し件数は1以上40以下にしてください" unless count.between?(1, 40)
      unless File.exist?(@state_path)
        raise "監視基準がありません。先に ruby bin/watch --sync-only を実行してください"
      end

      current = File.read(@state_path).strip
      raise "監視基準が空です。先に ruby bin/watch --sync-only を実行してください" if current.empty?

      older = @api.statuses(
        account_id: @config["fedibird"]["account_id"],
        max_id: current, limit: count)
      if older.length < count
        raise "#{count}件前のFedibird投稿を取得できないため、監視基準は変更しません"
      end

      rewound = older[count - 1]["id"].to_s
      raise "巻き戻し先の投稿IDを取得できないため、監視基準は変更しません" if rewound.empty?

      AtomicFile.write(@state_path, rewound)
      { from: current, to: rewound, count: count }
    rescue ArgumentError, TypeError
      raise "巻き戻し件数は1以上40以下にしてください"
    end

    private

    def record_state(statuses)
      newest = statuses.first
      return unless newest
      AtomicFile.write(@state_path, newest["id"].to_s)
    end

    def prepare_batch(since, statuses)
      stored = load_batch
      batch_id =
        if stored && stored["from_since"] == since
          stored.fetch("id")
        else
          SecureRandom.uuid
        end
      AtomicFile.write(@batch_path, JSON.pretty_generate(
        "id" => batch_id,
        "from_since" => since,
        "to_since" => statuses.first && statuses.first["id"].to_s))
      batch_id
    end

    def load_batch
      return nil unless File.exist?(@batch_path)

      JSON.parse(File.read(@batch_path))
    rescue JSON::ParserError
      raise "監視バッチ記録が壊れています: #{@batch_path}"
    end

    def discard_completed_batch(since)
      stored = load_batch
      finish_batch if stored && stored["to_since"] == since
    end

    def finish_batch
      File.delete(@batch_path) if File.exist?(@batch_path)
    end

    def enqueue_status(st, now:, batch_id:)
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
          Job.new(sns: sns, text: text, title: title,
                  media_paths: media_paths, media_urls: urls,
                  source_url: st["url"],
                  dedupe_key: "#{batch_id}:#{st['id']}:#{sns}",
                  created_at: now.iso8601),
          now: now)
      end
    end
  end
end
