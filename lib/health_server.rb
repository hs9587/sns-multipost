require "cgi"
require "fileutils"
require "json"
require "rbconfig"
require "securerandom"
require "time"
require "webrick"
require_relative "health_network"
require_relative "health_runtime"
require_relative "health_snapshot_cache"
require_relative "task_status"

module SnsMultipost
  class HealthServer
    attr_reader :network, :port

    def initialize(root:, selector:, port: 8765, task_name: "sns-multipost",
                   network_resolver: HealthNetwork.method(:resolve), clock: -> { Time.now },
                   refresh_interval: 10)
      @root = File.expand_path(root)
      @selector = selector
      @port = Integer(port)
      raise "ポートは1～65535で指定してください" unless @port.between?(1, 65_535)

      @clock = clock
      @refresh_interval = Float(refresh_interval)
      raise "状態更新間隔は0より大きく指定してください" unless @refresh_interval.positive?
      @network = network_resolver.call(selector)
      @task_name = task_name
      @started_at = clock.call
    rescue ArgumentError, TypeError
      raise "ポートは1～65535で指定してください"
    end

    def start
      FileUtils.mkdir_p(File.join(@root, "logs"))
      logger = WEBrick::Log.new(File.join(@root, "logs", "health.log"), WEBrick::Log::INFO)
      server = WEBrick::HTTPServer.new(
        BindAddress: network.fetch("address"), Port: port,
        AccessLog: [[logger, WEBrick::AccessLog::COMMON_LOG_FORMAT]], Logger: logger,
        ServerSoftware: "sns-multipost-health")
      state = runtime_state
      HealthSnapshotCache.save(
        @root, HealthSnapshotCache.initial(server_state: state, now: @clock.call))
      HealthRuntime.save(@root, state)
      state["worker_pid"] = start_snapshot_worker
      HealthRuntime.save(@root, state)
      server.mount_proc("/") { |request, response| respond(request, response, state) }
      %w[INT TERM].each { |signal| trap(signal) { server.shutdown } }
      server.start
    ensure
      HealthRuntime.remove(@root, pid: Process.pid)
      HealthSnapshotCache.remove(@root)
    end

    def runtime_state
      {
        "selector" => @selector,
        "kind" => network.fetch("kind"),
        "interface" => network.fetch("interface"),
        "resolved_ip" => network.fetch("address"),
        "port" => port,
        "pid" => Process.pid,
        "started_at" => @started_at.iso8601
      }
    end

    private

    def respond(request, response, state)
      script_nonce = SecureRandom.base64(18)
      set_headers(response, script_nonce: script_nonce)
      unless %w[GET HEAD].include?(request.request_method)
        response.status = 405
        response["Allow"] = "GET, HEAD"
        response.body = "Method Not Allowed\n"
        return
      end

      case request.path
      when "/"
        snapshot = current_snapshot(state)
        response["Content-Type"] = "text/html; charset=utf-8"
        response.body = html(snapshot, script_nonce: script_nonce)
      when "/health.json"
        snapshot = current_snapshot(state)
        response["Content-Type"] = "application/json; charset=utf-8"
        response.body = JSON.pretty_generate(snapshot) + "\n"
      when "/ping"
        response["Content-Type"] = "text/plain; charset=utf-8"
        response.body = "ok\n"
      else
        response.status = 404
        response["Content-Type"] = "text/plain; charset=utf-8"
        response.body = "Not Found\n"
      end
    rescue StandardError => e
      response.status = 500
      response["Content-Type"] = "application/json; charset=utf-8"
      response.body = JSON.generate("status" => "error", "error" => e.message) + "\n"
    end

    def start_snapshot_worker
      log = File.open(File.join(@root, "logs", "health-launch.log"), "ab")
      command = [
        RbConfig.ruby, File.join(@root, "bin", "health_snapshot_worker"),
        Process.pid.to_s, @refresh_interval.to_s, @task_name
      ]
      pid = Process.spawn(*command, chdir: @root, out: log, err: log)
      Process.detach(pid)
      pid
    ensure
      log&.close
    end

    def current_snapshot(state)
      snapshot = HealthSnapshotCache.load(@root)
      return snapshot unless snapshot.empty?

      HealthSnapshotCache.initial(
        server_state: state, now: @clock.call,
        error: "状態キャッシュを読み取れません")
    end

    def set_headers(response, script_nonce:)
      response["Cache-Control"] = "no-store"
      response["X-Content-Type-Options"] = "nosniff"
      response["Content-Security-Policy"] =
        "default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-#{script_nonce}'"
      response["Referrer-Policy"] = "no-referrer"
    end

    def html(snapshot, script_nonce:)
      status = snapshot.fetch("status")
      task = snapshot.fetch("task")
      runner = snapshot.fetch("runner")
      jobs = snapshot.fetch("jobs")
      server = snapshot.fetch("server")
      health_task = snapshot.fetch("health_task", {})
      request = snapshot.fetch("request")
      failed = jobs.fetch("recent_failed").map { |name| "<li>#{h(name)}</li>" }.join
      failed_count = jobs.fetch("recent_failed_count")
      last_run = runner["last_run"] || {}
      last_failure = runner["last_failure"] || {}
      <<~HTML
        <!doctype html>
        <html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <title>sns-multipost 状態</title>
        <style>
        body{font-family:system-ui,sans-serif;max-width:56rem;margin:2rem auto;padding:0 1rem;line-height:1.6}
        h2{margin:1.5rem 0 .5rem}
        dl{display:grid;grid-template-columns:minmax(14rem,19rem) minmax(0,1fr);gap:.25rem 1rem;margin:.5rem 0 1rem}
        dt{font-weight:700}
        dd{min-width:0;margin:0;overflow-wrap:anywhere}
        .ok{color:#087830}.failed,.error{color:#b42318}.disabled{color:#8a5700}
        code{word-break:break-all}
        @media(max-width:42rem){
          dl{grid-template-columns:1fr;gap:0}
          dd{margin:0 0 .6rem .75rem}
        }
        </style>
        </head><body>
        <h1>sns-multipost 状態</h1>
        <p class="#{h(status)}"><strong>#{h(status_label(status, failed_count: failed_count))}</strong></p>
        <h2>投稿タスク</h2>
        <dl>
          <dt>投稿スケジューラ状態</dt><dd>#{h(task_state(task))}</dd>
          <dt>投稿スケジューラの前回実行</dt><dd>#{h(format_time(task["LastRunTime"]))}</dd>
          <dt>投稿スケジューラの次回実行</dt><dd>#{h(format_time(task["NextRunTime"]))}</dd>
          <dt>投稿処理ラッパー最終</dt><dd>#{h(format_time(last_run["at"]))} / watch=#{h(last_run["watch_exit"])} run_queue=#{h(last_run["run_queue_exit"])} overall=#{h(last_run["overall_exit"])}</dd>
          <dt>投稿処理で最後に記録した異常</dt><dd>#{h(format_time(last_failure["at"]))}#{format_failure(last_failure)}</dd>
          <dt>完了した投稿ジョブの最新</dt><dd>#{h(jobs["latest_done"] || "なし")}</dd>
          <dt>未処理の失敗ジョブ</dt><dd>#{h(jobs["recent_failed_count"])}件</dd>
        </dl>
        #{failed.empty? ? "" : "<ul>#{failed}</ul>"}
        #{failed_count.positive? ? "<p>再投稿する場合は、重複を避けるため投稿済みでないことを確認してから<code>retry</code>してください。</p>" : ""}
        <h2>監視サーバー</h2>
        <dl>
          <dt>監視サーバー</dt><dd>#{h(server["selector"])} / #{h(server["resolved_ip"])}:#{h(server["port"])}</dd>
          <dt>監視サーバー起動日時</dt><dd>#{h(format_time(server["started_at"]))}</dd>
          <dt>常時起動用スケジューラ</dt><dd>#{h(health_task_state(health_task))}</dd>
          <dt>監視データ取得開始</dt><dd>#{h(format_time(request["started_at"]))}</dd>
          <dt>監視データ取得完了</dt><dd>#{h(format_time(request["completed_at"]))}</dd>
          <dt>監視データ取得時間</dt><dd>#{h(format_elapsed(request["elapsed_ms"]))}</dd>
          <dt>画面閲覧開始</dt><dd id="client-started-at">取得中</dd>
          <dt>画面受信時刻</dt><dd id="client-completed-at">取得中</dd>
          <dt>画面表示所要時間</dt><dd id="client-elapsed">取得中</dd>
        </dl>
        <p><a href="/health.json">JSON</a></p>
        <script nonce="#{h(script_nonce)}">
        (() => {
          const formatTime = (milliseconds) => {
            const value = new Date(milliseconds);
            return `${value.getFullYear()}年${value.getMonth() + 1}月${value.getDate()}日 ` +
              `${value.getHours()}:${String(value.getMinutes()).padStart(2, "0")}:` +
              `${String(value.getSeconds()).padStart(2, "0")}`;
          };
          const formatElapsed = (milliseconds) => {
            const seconds = milliseconds / 1000;
            if (seconds < 60) return `${seconds.toFixed(2)}秒`;
            const minutes = Math.floor(seconds / 60);
            return `${minutes}分${(seconds - minutes * 60).toFixed(2)}秒`;
          };
          document.getElementById("client-started-at").textContent = formatTime(performance.timeOrigin);
          document.getElementById("client-completed-at").textContent = formatTime(Date.now());
          document.getElementById("client-elapsed").textContent = formatElapsed(performance.now());
        })();
        </script>
        </body></html>
      HTML
    end

    def status_label(status, failed_count: 0)
      return "未処理の失敗記録があります（#{failed_count}件）" if failed_count.positive?

      {
        "ok" => "正常",
        "disabled" => "投稿タスク一時停止",
        "failed" => "定期実行で異常を記録しました",
        "error" => "状態取得エラー"
      }.fetch(status, status)
    end

    def task_state(task)
      return task["error"] if task["error"]

      state = task["State"].to_s
      label = TaskStatus::STATE_LABELS.fetch(state, state.empty? ? "不明" : state)
      state.empty? ? label : "#{label} (#{state})"
    end

    def health_task_state(task)
      return "確認できません: #{task['error']}" if task["error"]
      return "未登録" if task["registered"] == false
      return "確認中" unless task["registered"]

      "登録済み / #{task_state(task)}"
    end

    def format_failure(failure)
      return "" if failure.empty?

      " / watch=#{h(failure['watch_exit'])} run_queue=#{h(failure['run_queue_exit'])} " \
        "overall=#{h(failure['overall_exit'])}"
    end

    def format_time(value)
      return "なし" if value.nil? || value.to_s.empty?

      Time.iso8601(value.to_s).strftime("%Y年%-m月%-d日 %-H:%M:%S")
    rescue ArgumentError
      value.to_s
    end

    def format_elapsed(value)
      milliseconds = Integer(value)
      seconds = milliseconds / 1000.0
      return format("%.2f秒", seconds) if seconds < 60

      minutes = (seconds / 60).floor
      format("%d分%.2f秒", minutes, seconds - (minutes * 60))
    rescue ArgumentError, TypeError
      value.to_s
    end

    def h(value)
      CGI.escapeHTML(value.to_s)
    end
  end
end
