require "json"
require_relative "atomic_file"

module SnsMultipost
  module HealthSnapshotCache
    module_function

    STATE_FILE = "health_snapshot.json"

    def path(root)
      File.join(File.expand_path(root), "state", STATE_FILE)
    end

    def load(root)
      JSON.parse(File.read(path(root)))
    rescue Errno::ENOENT, JSON::ParserError
      {}
    end

    def save(root, snapshot)
      AtomicFile.write(path(root), JSON.pretty_generate(snapshot) + "\n")
    end

    def remove(root)
      File.delete(path(root)) if File.exist?(path(root))
      true
    end

    def initial(server_state:, now: Time.now, error: "状態を取得中です")
      {
        "status" => "error",
        "server_time" => now.iso8601,
        "server" => server_state,
        "task" => { "error" => error },
        "runner" => {},
        "jobs" => {
          "latest_done" => nil,
          "latest_done_at" => nil,
          "recent_failed_count" => 0,
          "recent_failed" => []
        },
        "request" => {
          "started_at" => now.iso8601,
          "completed_at" => now.iso8601,
          "elapsed_ms" => 0
        }
      }
    end
  end
end
