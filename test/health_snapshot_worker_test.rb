require_relative "test_helper"
require "health_snapshot_worker"
require "fileutils"

class HealthSnapshotWorkerTest < Minitest::Test
  def test_writes_snapshot_cache_for_server_to_read
    Dir.mktmpdir do |root|
      %w[done failed state].each { |name| FileUtils.mkdir_p(File.join(root, name)) }
      File.write(File.join(root, "done", "20260927-120000_tumblr_ok.json"), "{}")
      task = {
        "TaskName" => "sns-multipost", "State" => "Ready",
        "NextRunTime" => nil, "LastRunTime" => nil, "LastTaskResult" => 0
      }
      clock = -> { Time.new(2026, 9, 27, 12, 0, 0, "+09:00") }
      tick = 10.0
      worker = SnsMultipost::HealthSnapshotWorker.new(
        root: root, clock: clock, monotonic_clock: -> { tick += 0.25 })
      worker.instance_variable_set(
        :@snapshot,
        SnsMultipost::HealthSnapshot.new(root: root, clock: clock, task_query: -> { task }))

      worker.write_once({ "selector" => "nebula", "pid" => 123 })
      cached = SnsMultipost::HealthSnapshotCache.load(root)

      assert_equal "ok", cached.fetch("status")
      assert_equal "Ready", cached.dig("task", "State")
      assert_equal 250, cached.dig("request", "elapsed_ms")
    end
  end

  def test_records_worker_error_instead_of_raising
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "state"))
      worker = SnsMultipost::HealthSnapshotWorker.new(root: root)
      worker.instance_variable_set(:@snapshot, Object.new.tap do |snapshot|
        def snapshot.build(server_state:)
          raise "boom"
        end
      end)

      worker.write_once({ "selector" => "nebula", "pid" => 123 })
      cached = SnsMultipost::HealthSnapshotCache.load(root)

      assert_equal "error", cached.fetch("status")
      assert_includes cached.dig("task", "error"), "boom"
    end
  end
end
