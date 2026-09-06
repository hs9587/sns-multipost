require_relative "test_helper"
require "task_runner"

class TaskRunnerTest < Minitest::Test
  def test_runs_both_commands_and_returns_zero_when_both_succeed
    with_runner([0, 0]) do |runner, root, calls|
      assert_equal 0, runner.run
      assert_equal %w[watch run_queue], calls
      log = File.read(File.join(root, "logs", "cron.log"), encoding: "UTF-8")
      assert_includes log, "end watch_exit=0 run_queue_exit=0 overall_exit=0"
      status = SnsMultipost::TaskRunner.load_status(root)
      assert_equal 0, status.dig("last_run", "overall_exit")
      refute status.key?("last_failure")
    end
  end

  def test_runs_queue_and_returns_one_when_watch_fails
    with_runner([1, 0]) do |runner, root, calls|
      assert_equal 1, runner.run
      assert_equal %w[watch run_queue], calls
      status = SnsMultipost::TaskRunner.load_status(root)
      assert_equal 1, status.dig("last_failure", "watch_exit")
      assert_equal 0, status.dig("last_failure", "run_queue_exit")
    end
  end

  def test_preserves_last_failure_after_later_success
    Dir.mktmpdir do |root|
      exits = [0, 1, 0, 0]
      command_runner = lambda do |_command, _path, _log|
        exits.shift
      end
      clock_values = [
        Time.new(2026, 9, 6, 10, 0, 0, "+09:00"),
        Time.new(2026, 9, 6, 10, 10, 0, "+09:00")
      ]
      clock = lambda { clock_values.first }
      runner = SnsMultipost::TaskRunner.new(
        root: root, command_runner: command_runner, clock: clock)

      assert_equal 1, runner.run
      clock_values.shift
      assert_equal 0, runner.run
      status = SnsMultipost::TaskRunner.load_status(root)
      assert_equal 0, status.dig("last_run", "overall_exit")
      assert_equal 1, status.dig("last_failure", "overall_exit")
      output = SnsMultipost::TaskRunner.format_status(status)
      assert_includes output, "定期実行ラッパー最終: 2026年9月6日 10:10:00"
      assert_includes output, "最後に記録した異常: 2026年9月6日 10:00:00"
      assert_includes output, "watch=0 run_queue=1 overall=1"
    end
  end

  private

  def with_runner(exits)
    Dir.mktmpdir do |root|
      calls = []
      command_runner = lambda do |command, _path, log|
        calls << command
        log.write("#{command} output\n")
        exits.shift
      end
      runner = SnsMultipost::TaskRunner.new(
        root: root,
        clock: -> { Time.new(2026, 9, 6, 10, 0, 0, "+09:00") },
        command_runner: command_runner)
      yield runner, root, calls
    end
  end
end
