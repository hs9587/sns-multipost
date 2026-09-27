require_relative "test_helper"
require "health_snapshot"
require "fileutils"

class HealthSnapshotTest < Minitest::Test
  def test_builds_read_only_operational_snapshot
    Dir.mktmpdir do |root|
      %w[done failed state].each { |name| FileUtils.mkdir_p(File.join(root, name)) }
      File.write(File.join(root, "done", "20260926-070000_tumblr_ok.json"), "{}")
      task = {
        "TaskName" => "sns-multipost", "State" => "Ready",
        "NextRunTime" => "2026-09-26T07:15:00+09:00",
        "LastRunTime" => "2026-09-26T07:05:00+09:00", "LastTaskResult" => 0
      }
      snapshot = SnsMultipost::HealthSnapshot.new(
        root: root,
        clock: -> { Time.new(2026, 9, 26, 7, 10, 0, "+09:00") },
        task_query: -> { task }).build(server_state: { "selector" => "nebula" })

      assert_equal "ok", snapshot.fetch("status")
      assert_equal "Ready", snapshot.dig("task", "State")
      assert_equal 0, snapshot.dig("jobs", "recent_failed_count")
      assert_equal "nebula", snapshot.dig("server", "selector")
    end
  end

  def test_reports_recent_failed_job_name_without_exposing_job_body
    Dir.mktmpdir do |root|
      %w[done failed state].each { |name| FileUtils.mkdir_p(File.join(root, name)) }
      File.write(File.join(root, "done", "20260926-070000_tumblr_ok.json"), "{}")
      File.write(File.join(root, "failed", "20260926-070000_jotter_failed.json"), "{}")
      task = { "TaskName" => "sns-multipost", "State" => "Ready" }

      snapshot = SnsMultipost::HealthSnapshot.new(
        root: root, task_query: -> { task }).build(server_state: {})

      assert_equal "failed", snapshot.fetch("status")
      assert_equal ["20260926-070000_jotter_failed.json"],
                   snapshot.dig("jobs", "recent_failed")
    end
  end

  def test_hides_stale_next_run_time_when_task_is_disabled
    Dir.mktmpdir do |root|
      %w[done failed state].each { |name| FileUtils.mkdir_p(File.join(root, name)) }
      task = {
        "TaskName" => "sns-multipost", "State" => "Disabled",
        "NextRunTime" => "2026-09-26T22:05:00+09:00"
      }

      snapshot = SnsMultipost::HealthSnapshot.new(
        root: root, task_query: -> { task }).build(server_state: {})

      assert_equal "disabled", snapshot.fetch("status")
      assert_nil snapshot.dig("task", "NextRunTime")
      assert_equal "2026-09-26T22:05:00+09:00", task["NextRunTime"]
    end
  end

  def test_times_out_slow_task_query_instead_of_blocking_health_page
    Dir.mktmpdir do |root|
      %w[done failed state].each { |name| FileUtils.mkdir_p(File.join(root, name)) }

      snapshot = SnsMultipost::HealthSnapshot.new(
        root: root,
        task_timeout: 0.01,
        task_query: -> { sleep 1 }).build(server_state: {})

      assert_equal "error", snapshot.fetch("status")
      assert_includes snapshot.dig("task", "error"), "状態取得または待機が1.01秒以内に完了しませんでした"
    end
  end

  def test_times_out_while_another_task_query_holds_the_mutex
    Dir.mktmpdir do |root|
      %w[done failed state].each { |name| FileUtils.mkdir_p(File.join(root, name)) }
      entered = Queue.new
      release = Queue.new
      snapshot = SnsMultipost::HealthSnapshot.new(
        root: root,
        task_timeout: 0.02,
        task_query: lambda {
          entered << true
          release.pop
          { "TaskName" => "sns-multipost", "State" => "Ready" }
        })
      holder = Thread.new { snapshot.build(server_state: {}) }
      entered.pop

      result = snapshot.build(server_state: {})

      assert_equal "error", result.fetch("status")
      assert_includes result.dig("task", "error"), "状態取得または待機"
    ensure
      release << true
      holder&.join(1)
    end
  end
end
