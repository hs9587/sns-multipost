require "fileutils"
require "open3"
require "rbconfig"
require "time"
require_relative "token_store"

module SnsMultipost
  class TaskRunner
    STATUS_FILE = "task_run_status.json"

    def initialize(root:, ruby_path: RbConfig.ruby, clock: -> { Time.now }, command_runner: nil)
      @root = File.expand_path(root)
      @ruby_path = File.expand_path(ruby_path)
      @clock = clock
      @command_runner = command_runner || method(:run_command)
    end

    def run
      FileUtils.mkdir_p(File.join(@root, "logs"))
      File.open(log_path, "ab") do |log|
        log.sync = true
        write_line(log, "start cwd=#{@root}")
        watch_exit = command_exit("watch", log)
        run_queue_exit = command_exit("run_queue", log)
        overall_exit = watch_exit.zero? && run_queue_exit.zero? ? 0 : 1
        run_status = {
          "at" => @clock.call.iso8601,
          "watch_exit" => watch_exit,
          "run_queue_exit" => run_queue_exit,
          "overall_exit" => overall_exit
        }
        save_status(run_status)
        write_line(
          log,
          "end watch_exit=#{watch_exit} run_queue_exit=#{run_queue_exit} overall_exit=#{overall_exit}")
        overall_exit
      end
    rescue StandardError => e
      record_fatal_error(e)
      1
    end

    def self.load_status(root)
      TokenStore.new(status_path(root)).load
    rescue JSON::ParserError
      {}
    end

    def self.format_status(status)
      last_run = status["last_run"]
      last_failure = status["last_failure"]
      lines = []
      lines << if last_run
                 "定期実行ラッパー最終: #{format_run(last_run)}"
               else
                 "定期実行ラッパー最終: 記録なし"
               end
      lines << "最後に記録した異常: #{format_run(last_failure)}" if last_failure
      lines.join("\n")
    end

    def self.status_path(root)
      File.join(File.expand_path(root), "state", STATUS_FILE)
    end

    def self.format_run(run)
      at = Time.iso8601(run.fetch("at")).strftime("%Y年%-m月%-d日 %-H:%M:%S")
      "#{at} watch=#{run.fetch('watch_exit')} run_queue=#{run.fetch('run_queue_exit')} " \
        "overall=#{run.fetch('overall_exit')}"
    rescue KeyError, ArgumentError
      "記録を解析できません"
    end

    private

    def command_exit(command, log)
      path = File.join(@root, "bin", command)
      Integer(@command_runner.call(command, path, log))
    rescue StandardError => e
      write_line(log, "ERROR: #{command}を実行できません: #{e.class}: #{e.message}")
      1
    end

    def run_command(_command, path, log)
      exit_status = nil
      Open3.popen2e(@ruby_path, path, chdir: @root) do |_stdin, output, wait_thread|
        output.each { |chunk| log.write(chunk) }
        exit_status = wait_thread.value.exitstatus
      end
      exit_status || 1
    end

    def save_status(run_status)
      store = TokenStore.new(self.class.status_path(@root))
      status = store.load
      status["last_run"] = run_status
      status["last_failure"] = run_status unless run_status["overall_exit"].zero?
      store.save(status)
    end

    def record_fatal_error(error)
      now = @clock.call
      FileUtils.mkdir_p(File.dirname(log_path))
      File.open(log_path, "ab") do |log|
        write_line(log, "FATAL: task runner failed: #{error.class}: #{error.message}", now: now)
      end
      run_status = {
        "at" => now.iso8601,
        "watch_exit" => 1,
        "run_queue_exit" => 1,
        "overall_exit" => 1
      }
      save_status(run_status)
    rescue StandardError
      nil
    end

    def log_path
      File.join(@root, "logs", "cron.log")
    end

    def write_line(log, message, now: @clock.call)
      log.write("[#{now.strftime('%Y/%m/%d %H:%M:%S.%L')}] #{message}\r\n")
    end
  end
end
