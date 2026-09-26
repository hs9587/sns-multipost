require "time"
require_relative "job_history"
require_relative "task_runner"
require_relative "task_status"

module SnsMultipost
  class HealthSnapshot
    def initialize(root:, task_name: "sns-multipost", clock: -> { Time.now }, task_query: nil)
      @root = File.expand_path(root)
      @task_name = task_name
      @clock = clock
      @task_query = task_query || -> { TaskStatus.query(@task_name) }
    end

    def build(server_state:)
      now = @clock.call
      task = safe_task
      runner = TaskRunner.load_status(@root)
      history = JobHistory.snapshot(
        done_directory: File.join(@root, "done"),
        failed_directory: File.join(@root, "failed"))
      {
        "status" => overall_status(task, runner, history),
        "server_time" => now.iso8601,
        "server" => server_state,
        "task" => task,
        "runner" => runner,
        "jobs" => {
          "latest_done" => history[:latest_done],
          "latest_done_at" => history[:latest_done_timestamp],
          "recent_failed_count" => history[:failed_jobs].length,
          "recent_failed" => history[:failed_jobs].first(3)
        }
      }
    end

    private

    def safe_task
      task = @task_query.call.dup
      task["NextRunTime"] = TaskStatus.effective_next_run(task)
      task
    rescue StandardError => e
      { "TaskName" => @task_name, "error" => e.message }
    end

    def overall_status(task, runner, history)
      return "error" if task["error"]
      return "failed" if history[:failed_jobs].any?
      return "failed" if runner.dig("last_run", "overall_exit").to_i != 0
      return "disabled" if task["State"] == "Disabled"

      "ok"
    end
  end
end
