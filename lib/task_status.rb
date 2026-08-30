require "json"
require "open3"
require "time"

module SnsMultipost
  module TaskStatus
    module_function

    STATE_LABELS = {
      "Disabled" => "一時停止",
      "Ready" => "有効・待機中",
      "Running" => "実行中",
      "Queued" => "実行待ち",
      "Unknown" => "不明"
    }.freeze

    def query(task_name, capture3: Open3.method(:capture3))
      escaped_name = task_name.gsub("'", "''")
      script = <<~POWERSHELL
        $ErrorActionPreference = 'Stop'
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
        $task = Get-ScheduledTask -TaskName '#{escaped_name}'
        $info = Get-ScheduledTaskInfo -TaskName '#{escaped_name}'
        [ordered]@{
          TaskName = $task.TaskName
          State = $task.State.ToString()
          NextRunTime = if ($info.NextRunTime -and $info.NextRunTime.Year -gt 1900) { $info.NextRunTime.ToString('o') } else { $null }
          LastRunTime = if ($info.LastRunTime -and $info.LastRunTime.Year -gt 1900) { $info.LastRunTime.ToString('o') } else { $null }
          LastTaskResult = [Int64]$info.LastTaskResult
        } | ConvertTo-Json -Compress
      POWERSHELL
      stdout, stderr, status = capture3.call(
        "powershell.exe", "-NoProfile", "-NonInteractive",
        "-ExecutionPolicy", "Bypass", "-Command", script)
      unless status.success?
        message = utf8(stderr).strip
        message = "終了コード#{status.exitstatus}" if message.empty?
        raise "Windowsタスク「#{task_name}」を確認できません: #{message}"
      end

      JSON.parse(utf8(stdout))
    rescue JSON::ParserError => e
      raise "Windowsタスク「#{task_name}」の結果を解析できません: #{e.message}"
    end

    def set_enabled(task_name, enabled:, capture3: Open3.method(:capture3))
      escaped_name = task_name.gsub("'", "''")
      command = enabled ? "Enable-ScheduledTask" : "Disable-ScheduledTask"
      script = <<~POWERSHELL
        $ErrorActionPreference = 'Stop'
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
        #{command} -TaskName '#{escaped_name}' | Out-Null
      POWERSHELL
      _stdout, stderr, status = capture3.call(
        "powershell.exe", "-NoProfile", "-NonInteractive",
        "-ExecutionPolicy", "Bypass", "-Command", script)
      return true if status.success?

      message = utf8(stderr).strip
      message = "終了コード#{status.exitstatus}" if message.empty?
      raise "Windowsタスク「#{task_name}」を変更できません: #{message}"
    end

    def register(task_name, runner_path:, minutes:, capture3: Open3.method(:capture3))
      runner = File.expand_path(runner_path)
      raise "タスク用バッチが見つかりません: #{runner}" unless File.file?(runner)

      interval = Integer(minutes)
      raise "実行間隔は1～1440分で指定してください" unless interval.between?(1, 1440)

      _stdout, stderr, status = capture3.call(
        "schtasks.exe", "/Create", "/TN", task_name,
        "/TR", %Q{"#{runner}"}, "/SC", "MINUTE", "/MO", interval.to_s, "/F")
      unless status.success?
        message = utf8(stderr).strip
        message = "終了コード#{status.exitstatus}" if message.empty?
        raise "Windowsタスク「#{task_name}」を登録できません: #{message}"
      end

      escaped_name = task_name.gsub("'", "''")
      script = <<~POWERSHELL
        $ErrorActionPreference = 'Stop'
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
        Set-ScheduledTask -TaskName '#{escaped_name}' -Settings $settings | Out-Null
      POWERSHELL
      _stdout, stderr, status = capture3.call(
        "powershell.exe", "-NoProfile", "-NonInteractive",
        "-ExecutionPolicy", "Bypass", "-Command", script)
      return true if status.success?

      message = utf8(stderr).strip
      message = "終了コード#{status.exitstatus}" if message.empty?
      raise "Windowsタスク「#{task_name}」は登録されましたが、運用設定を変更できません: #{message}"
    rescue ArgumentError, TypeError
      raise "実行間隔は1～1440分で指定してください"
    end

    def unregister(task_name, capture3: Open3.method(:capture3))
      _stdout, stderr, status = capture3.call(
        "schtasks.exe", "/Delete", "/TN", task_name, "/F")
      return true if status.success?

      message = utf8(stderr).strip
      message = "終了コード#{status.exitstatus}" if message.empty?
      raise "Windowsタスク「#{task_name}」を解除できません: #{message}"
    end

    def format(status, now: Time.now)
      state = status.fetch("State").to_s
      next_run = status["NextRunTime"]
      next_run = nil if state == "Disabled"
      [
        "タスク: #{status.fetch('TaskName')}",
        "現在時刻: #{format_time(now)}",
        "状態: #{STATE_LABELS.fetch(state, state)} (#{state})",
        "次回実行: #{next_run ? format_time(next_run) : 'なし'}",
        "前回実行: #{status['LastRunTime'] ? format_time(status['LastRunTime']) : 'なし'}",
        "前回結果: #{format_result(status.fetch('LastTaskResult'))}"
      ].join("\n")
    end

    def format_time(value)
      time = value.is_a?(Time) ? value : Time.iso8601(value.to_s)
      time.strftime("%Y年%-m月%-d日 %-H:%M:%S")
    end

    def format_result(value)
      result = Integer(value)
      return "成功 (0)" if result.zero?
      return "投稿失敗あり (1)" if result == 1

      Kernel.format("%d (0x%08X)", result, result & 0xffffffff)
    end

    def format_failed_jobs(directory, limit: 3)
      jobs = Dir.children(directory)
                .select { |name| name.end_with?(".json") && File.file?(File.join(directory, name)) }
                .sort
                .reverse
      lines = ["failed内のジョブ: #{jobs.length}件（保留分を含む・自動判定ではありません）"]
      jobs.first(limit).each do |name|
        lines << "  #{name}"
      end
      remaining = jobs.length - limit
      lines << "  ほか#{remaining}件" if remaining.positive?
      lines.join("\n")
    end

    def utf8(string)
      string.to_s.dup.force_encoding(Encoding::UTF_8).scrub
    end
  end
end
