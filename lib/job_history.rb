require "time"
require "json"

module SnsMultipost
  module JobHistory
    module_function

    TIMESTAMP_PATTERN = /\A(\d{8}-\d{6})_/.freeze

    def snapshot(done_directory:, failed_directory:, include_all: false)
      done_jobs = job_names(done_directory)
      failed_jobs = job_names(failed_directory)
      latest_done_timestamp = timestamp(done_jobs.first)
      selected = if include_all || latest_done_timestamp.nil?
                   failed_jobs
                 else
                   failed_jobs.select do |name|
                     job_timestamp = timestamp(name)
                     job_timestamp.nil? || job_timestamp >= latest_done_timestamp
                   end
                 end
      {
        latest_done: done_jobs.first,
        latest_done_timestamp: latest_done_timestamp,
        failed_jobs: selected,
        delivery_states: selected.to_h do |name|
          [name, delivery_state(failed_directory, name)]
        end.compact,
        all_failed_count: failed_jobs.length,
        include_all: include_all
      }
    end

    def format_summary(history, limit: 3)
      timestamp_text = format_timestamp(history[:latest_done_timestamp])
      lines = ["done最新時刻: #{timestamp_text}"]
      label = if history[:latest_done_timestamp]
                "done最新と同時刻以降のfailed"
              else
                "failed内のジョブ"
              end
      jobs = history.fetch(:failed_jobs)
      lines << "#{label}: #{jobs.length}件（保留分を含む・自動判定ではありません）"
      jobs.first(limit).each { |name| lines << "  #{job_label(history, name)}" }
      remaining = jobs.length - limit
      lines << "  ほか#{remaining}件" if remaining.positive?
      lines.join("\n")
    end

    def format_list(history, offset:, limit:)
      jobs = history.fetch(:failed_jobs)
      shown = jobs.slice(offset, limit) || []
      lines = ["done最新時刻: #{format_timestamp(history[:latest_done_timestamp])}"]
      if history[:latest_done]
        lines << "done最新ジョブ: #{history[:latest_done]}"
      end
      lines << if history[:include_all]
                 "対象: failed内の全#{jobs.length}件（古い保留分を含む）"
               elsif history[:latest_done_timestamp]
                 "対象: done最新と同時刻以降のfailed #{jobs.length}件"
               else
                 "対象: failed内の全#{jobs.length}件（doneなし）"
               end
      if shown.empty?
        lines << "表示: 0件"
      else
        lines << "表示: #{offset + 1}～#{offset + shown.length}件目 / #{jobs.length}件"
        shown.each { |name| lines << "  #{job_label(history, name)}" }
      end
      lines.join("\n")
    end

    def job_names(directory)
      return [] unless Dir.exist?(directory)

      Dir.children(directory)
         .select { |name| name.end_with?(".json") && File.file?(File.join(directory, name)) }
         .sort
         .reverse
    end

    def timestamp(name)
      name.to_s[TIMESTAMP_PATTERN, 1]
    end

    def delivery_state(directory, name)
      data = JSON.parse(File.read(File.join(directory, name)))
      data["delivery_state"].to_s.then { |state| state.empty? ? nil : state }
    rescue Errno::ENOENT, JSON::ParserError
      nil
    end

    def job_label(history, name)
      state = history.fetch(:delivery_states, {})[name]
      state == "unknown" ? "#{name} [投稿結果不明]" : name
    end

    def format_timestamp(value)
      return "なし" unless value

      Time.strptime(value, "%Y%m%d-%H%M%S").strftime("%Y年%-m月%-d日 %-H:%M:%S")
    end
  end
end
