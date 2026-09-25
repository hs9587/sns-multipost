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
end
