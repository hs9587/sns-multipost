require "time"
require_relative "health_runtime"
require_relative "health_snapshot"
require_relative "health_snapshot_cache"

module SnsMultipost
  class HealthSnapshotWorker
    def initialize(root:, task_name: "sns-multipost", clock: -> { Time.now },
                   monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @root = File.expand_path(root)
      @clock = clock
      @monotonic_clock = monotonic_clock
      @snapshot = HealthSnapshot.new(root: @root, task_name: task_name, clock: clock)
    end

    def run(parent_pid:, interval: 10)
      delay = Float(interval)
      raise "状態更新間隔は0より大きく指定してください" unless delay.positive?

      loop do
        state = HealthRuntime.load(@root)
        break unless state["pid"].to_i == parent_pid.to_i
        break unless HealthRuntime.process_alive?(parent_pid)

        write_once(state)
        sleep(delay)
      end
    end

    def write_once(server_state)
      started_at = @clock.call
      started_tick = @monotonic_clock.call
      snapshot = @snapshot.build(server_state: server_state)
      completed_at = @clock.call
      elapsed_ms = ((@monotonic_clock.call - started_tick) * 1000).round
      HealthSnapshotCache.save(@root, snapshot.merge(
        "request" => {
          "started_at" => started_at.iso8601,
          "completed_at" => completed_at.iso8601,
          "elapsed_ms" => elapsed_ms
        }))
    rescue StandardError => e
      now = @clock.call
      HealthSnapshotCache.save(@root, HealthSnapshotCache.initial(
        server_state: server_state, now: now,
        error: "状態の定期更新に失敗しました: #{e.message}"))
    end
  end
end
