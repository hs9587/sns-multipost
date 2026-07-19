require_relative "test_helper"
require "runner"
require "config"
require "job_queue"
require "poster/all"

class RunnerTest < Minitest::Test
  def test_ok_and_failed_jobs_move_to_their_dirs
    Dir.mktmpdir do |dir|
      config = SnsMultipost::Config.new({ "dry_run" => true })
      q = SnsMultipost::JobQueue.new(dir)
      q.enqueue(SnsMultipost::Job.new(sns: "fedibird", text: "a"))
      q.enqueue(SnsMultipost::Job.new(sns: "unknown-sns", text: "b"))

      results = SnsMultipost::Runner.new(config: config, queue: q).run

      assert_equal 2, results.size
      assert_equal 1, Dir[File.join(dir, "done", "*.json")].size
      assert_equal 1, Dir[File.join(dir, "failed", "*.json")].size
      failed = JSON.parse(File.read(Dir[File.join(dir, "failed", "*.json")].first))
      assert_match(/poster 未実装/, failed["last_error"])
    end
  end
end
