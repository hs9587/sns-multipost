require_relative "test_helper"
require "task_status"
require "fileutils"
require "rbconfig"

class TaskStatusTest < Minitest::Test
  FakeStatus = Struct.new(:success?, :exitstatus)

  def test_formats_disabled_task_without_next_run
    status = {
      "TaskName" => "sns-multipost",
      "State" => "Disabled",
      "NextRunTime" => "2026-08-29T06:47:00+09:00",
      "LastRunTime" => "2026-08-28T18:47:01+09:00",
      "LastTaskResult" => 1
    }

    output = SnsMultipost::TaskStatus.format(
      status, now: Time.new(2026, 8, 29, 6, 11, 39, "+09:00"))

    assert_includes output, "状態: 一時停止 (Disabled)"
    assert_includes output, "次回実行: なし"
    assert_includes output, "前回実行: 2026年8月28日 18:47:01"
    assert_includes output, "前回結果: 投稿失敗あり (1)"
  end

  def test_formats_ready_task_and_success
    status = {
      "TaskName" => "sns-multipost",
      "State" => "Ready",
      "NextRunTime" => "2026-08-29T06:47:00+09:00",
      "LastRunTime" => nil,
      "LastTaskResult" => 0
    }

    output = SnsMultipost::TaskStatus.format(status)

    assert_includes output, "状態: 有効・待機中 (Ready)"
    assert_includes output, "次回実行: 2026年8月29日 6:47:00"
    assert_includes output, "前回実行: なし"
    assert_includes output, "前回結果: 成功 (0)"
  end

  def test_formats_other_result_as_decimal_and_hex
    assert_equal "267009 (0x00041301)",
                 SnsMultipost::TaskStatus.format_result(267_009)
  end

  def test_queries_task_scheduler_via_com_without_powershell
    task = Struct.new(:Name, :State, :NextRunTime, :LastRunTime, :LastTaskResult).new(
      "sns-multipost", 3,
      Time.new(2026, 9, 27, 14, 5, 0, "+09:00"),
      Time.new(2026, 9, 27, 13, 55, 1, "+09:00"), 0)
    folder = Object.new
    folder.define_singleton_method(:GetTask) do |name|
      raise "wrong task" unless name == "sns-multipost"
      task
    end
    service = Object.new
    service.define_singleton_method(:Connect) { true }
    service.define_singleton_method(:GetFolder) do |path|
      raise "wrong folder" unless path == "\\"
      folder
    end

    status = SnsMultipost::TaskStatus.query_via_com(
      "sns-multipost", service_factory: -> { service })

    assert_equal "Ready", status.fetch("State")
    assert_equal "2026-09-27T14:05:00+09:00", status.fetch("NextRunTime")
    assert_equal "2026-09-27T13:55:01+09:00", status.fetch("LastRunTime")
    assert_equal 0, status.fetch("LastTaskResult")
  end

  def test_external_command_timeout_terminates_process
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    assert_raises(SnsMultipost::TaskStatus::CommandTimedOut) do
      SnsMultipost::TaskStatus.capture3_with_timeout(
        RbConfig.ruby, "-e", "sleep 30", timeout: 0.05)
    end

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    assert_operator elapsed, :<, 2
  end

  def test_external_command_timeout_terminates_descendants_holding_output_pipe
    child_code = "sleep 30"
    parent_code = <<~RUBY
      Process.spawn(
        #{RbConfig.ruby.dump}, "-e", #{child_code.dump},
        out: $stdout, err: $stderr)
      sleep 30
    RUBY
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    assert_raises(SnsMultipost::TaskStatus::CommandTimedOut) do
      SnsMultipost::TaskStatus.capture3_with_timeout(
        RbConfig.ruby, "-e", parent_code, timeout: 0.1)
    end

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    assert_operator elapsed, :<, 3
  end

  def test_set_enabled_uses_windows_task_commands
    scripts = []
    capture3 = lambda do |*_args|
      scripts << _args.last
      ["", "", FakeStatus.new(true, 0)]
    end

    assert SnsMultipost::TaskStatus.set_enabled(
      "sns-multipost", enabled: true, capture3: capture3)
    assert SnsMultipost::TaskStatus.set_enabled(
      "sns-multipost", enabled: false, capture3: capture3)
    assert_includes scripts[0], "Enable-ScheduledTask -TaskName 'sns-multipost'"
    assert_includes scripts[1], "Disable-ScheduledTask -TaskName 'sns-multipost'"
  end

  def test_set_enabled_escapes_single_quote_in_task_name
    script = nil
    capture3 = lambda do |*args|
      script = args.last
      ["", "", FakeStatus.new(true, 0)]
    end

    SnsMultipost::TaskStatus.set_enabled(
      "task'name", enabled: false, capture3: capture3)

    assert_includes script, "-TaskName 'task''name'"
  end

  def test_register_creates_repeating_task_and_sets_operational_settings
    Dir.mktmpdir do |dir|
      runner = File.join(dir, "cron wrapper.bat")
      FileUtils.touch(runner)
      calls = []
      capture3 = lambda do |*args|
        calls << args
        ["", "", FakeStatus.new(true, 0)]
      end

      assert SnsMultipost::TaskStatus.register(
        "sns-multipost", runner_path: runner, minutes: 10, capture3: capture3)
      assert_equal [
        "schtasks.exe", "/Create", "/TN", "sns-multipost", "/TR", %Q{"#{runner}"},
        "/SC", "MINUTE", "/MO", "10", "/F"
      ], calls[0]
      assert_includes calls[1].last, "AllowStartIfOnBatteries"
      assert_includes calls[1].last, "DontStopIfGoingOnBatteries"
      assert_includes calls[1].last, "MultipleInstances IgnoreNew"
    end
  end

  def test_register_runs_ruby_runner_with_selected_ruby
    Dir.mktmpdir do |dir|
      runner = File.join(dir, "task_run")
      ruby = File.join(dir, "ruby.exe")
      FileUtils.touch(runner)
      FileUtils.touch(ruby)
      calls = []
      capture3 = lambda do |*args|
        calls << args
        ["", "", FakeStatus.new(true, 0)]
      end

      assert SnsMultipost::TaskStatus.register(
        "sns-multipost", runner_path: runner, ruby_path: ruby,
        minutes: 10, capture3: capture3)
      assert_equal %Q{"#{ruby}" "#{runner}"}, calls[0][5]
    end
  end

  def test_register_rejects_missing_runner_and_invalid_interval
    error = assert_raises(RuntimeError) do
      SnsMultipost::TaskStatus.register(
        "sns-multipost", runner_path: "missing.bat", minutes: 10)
    end
    assert_match(/実行ラッパーが見つかりません/, error.message)

    Dir.mktmpdir do |dir|
      runner = File.join(dir, "cron.bat")
      FileUtils.touch(runner)
      error = assert_raises(RuntimeError) do
        SnsMultipost::TaskStatus.register(
          "sns-multipost", runner_path: runner, minutes: 0)
      end
      assert_match(/1～1440分/, error.message)
    end
  end

  def test_unregister_deletes_only_named_task_registration
    call = nil
    capture3 = lambda do |*args|
      call = args
      ["", "", FakeStatus.new(true, 0)]
    end

    assert SnsMultipost::TaskStatus.unregister(
      "sns-multipost", capture3: capture3)
    assert_equal ["schtasks.exe", "/Delete", "/TN", "sns-multipost", "/F"], call
  end
end
