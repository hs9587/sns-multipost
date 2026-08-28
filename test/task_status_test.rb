require_relative "test_helper"
require "task_status"

class TaskStatusTest < Minitest::Test
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
end
