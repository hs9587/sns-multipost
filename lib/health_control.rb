require "fileutils"
require "open3"
require "rbconfig"
require_relative "health_network"
require_relative "health_runtime"
require_relative "task_status"

module SnsMultipost
  class HealthControl
    TASK_NAME = "sns-multipost-health"

    def initialize(root:, ruby_path: RbConfig.ruby, task_name: TASK_NAME,
                   capture3: Open3.method(:capture3), sleeper: ->(seconds) { sleep(seconds) })
      @root = File.expand_path(root)
      @ruby_path = File.expand_path(ruby_path)
      @task_name = task_name
      @capture3 = capture3
      @sleeper = sleeper
    end

    def start(selector:, port: 8765)
      raise "監視サーバーはすでに稼働しています" if HealthRuntime.reachable?(HealthRuntime.load(@root))

      network = HealthNetwork.resolve(selector)
      selected_port = validate_port(port)
      target = { "resolved_ip" => network.fetch("address"), "port" => selected_port }
      if HealthRuntime.port_open?(target)
        raise "#{network.fetch('address')}:#{selected_port}は別のプロセスが使用中です"
      end
      FileUtils.mkdir_p(File.join(@root, "logs"))
      log = File.open(File.join(@root, "logs", "health-launch.log"), "ab")
      command = [@ruby_path, server_path, "--bind", selector, "--port", selected_port.to_s]
      pid = Process.spawn(*command, chdir: @root, out: log, err: log, new_pgroup: true)
      Process.detach(pid)
      wait_until_running
      HealthRuntime.load(@root)
    ensure
      log&.close
    end

    def stop
      state = HealthRuntime.load(@root)
      task_registered = registered?
      end_task if task_registered
      return task_registered if state.empty?

      pid = Integer(state.fetch("pid"))
      @capture3.call("taskkill.exe", "/PID", pid.to_s, "/T", "/F")
      20.times do
        break unless HealthRuntime.reachable?(state)
        @sleeper.call(0.1)
      end
      raise "監視サーバーを停止できません（PID #{pid}）" if HealthRuntime.reachable?(state)

      HealthRuntime.remove(@root)
      true
    rescue ArgumentError, KeyError
      HealthRuntime.remove(@root)
      false
    end

    def register(selector:, port: 8765)
      HealthNetwork.resolve(selector)
      selected_port = validate_port(port)
      command = %Q{"#{@ruby_path}" "#{server_path}" --bind "#{selector}" --port #{selected_port}}
      _stdout, stderr, status = @capture3.call(
        "schtasks.exe", "/Create", "/TN", @task_name, "/TR", command,
        "/SC", "ONLOGON", "/F")
      command_error!("登録", stderr, status) unless status.success?

      escaped = @task_name.gsub("'", "''")
      script = <<~POWERSHELL
        $ErrorActionPreference = 'Stop'
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
        Set-ScheduledTask -TaskName '#{escaped}' -Settings $settings | Out-Null
      POWERSHELL
      _stdout, stderr, status = @capture3.call(
        "powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
        "-Command", script)
      command_error!("運用設定", stderr, status) unless status.success?
      run_task
      wait_until_running
      true
    end

    def unregister
      end_task if registered?
      TaskStatus.unregister(@task_name, capture3: @capture3)
      HealthRuntime.remove(@root)
      true
    end

    def registered?
      TaskStatus.query(@task_name, capture3: @capture3)
      true
    rescue StandardError
      false
    end

    def registration
      TaskStatus.query(@task_name, capture3: @capture3)
    rescue StandardError
      nil
    end

    def start_registered
      raise "監視サーバー用Windowsタスクは未登録です" unless registered?

      run_task
      wait_until_running
      HealthRuntime.load(@root)
    end

    private

    def server_path
      File.join(@root, "bin", "health_server")
    end

    def run_task
      _stdout, stderr, status = @capture3.call("schtasks.exe", "/Run", "/TN", @task_name)
      command_error!("起動", stderr, status) unless status.success?
    end

    def end_task
      @capture3.call("schtasks.exe", "/End", "/TN", @task_name)
    end

    def wait_until_running
      50.times do
        state = HealthRuntime.load(@root)
        return true if HealthRuntime.reachable?(state)
        @sleeper.call(0.1)
      end
      raise "監視サーバーの起動を確認できません。logs/health-launch.logを確認してください"
    end

    def command_error!(operation, stderr, status)
      message = TaskStatus.utf8(stderr).strip
      message = "終了コード#{status.exitstatus}" if message.empty?
      raise "監視サーバー用Windowsタスクを#{operation}できません: #{message}"
    end

    def validate_port(value)
      port = Integer(value)
      raise "ポートは1～65535で指定してください" unless port.between?(1, 65_535)

      port
    rescue ArgumentError, TypeError
      raise "ポートは1～65535で指定してください"
    end
  end
end
