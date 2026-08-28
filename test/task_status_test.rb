require_relative "test_helper"
require "task_status"
require "fileutils"

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

  def test_register_rejects_missing_runner_and_invalid_interval
    error = assert_raises(RuntimeError) do
      SnsMultipost::TaskStatus.register(
        "sns-multipost", runner_path: "missing.bat", minutes: 10)
    end
    assert_match(/バッチが見つかりません/, error.message)

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
