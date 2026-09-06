require_relative "test_helper"
require "runner"
require "config"
require "job_queue"
require "poster/all"
require "delivery_error"

class RunnerTest < Minitest::Test
  def test_exit_status_is_zero_when_all_jobs_succeed
    results = [[Object.new, :ok, {}], [Object.new, :ok, {}]]

    assert_equal 0, SnsMultipost::Runner.exit_status(results)
    assert_equal 0, SnsMultipost::Runner.exit_status([])
  end

  def test_exit_status_is_one_when_any_job_fails
    results = [[Object.new, :ok, {}], [Object.new, :failed, "error"]]

    assert_equal 1, SnsMultipost::Runner.exit_status(results)
  end

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

  def test_marks_delivery_unknown_failure_in_job
    Dir.mktmpdir do |dir|
      name = "unknown-delivery-test"
      klass = Class.new(SnsMultipost::Poster::Base) do
        def perform(_job)
          raise SnsMultipost::DeliveryUnknownError, "confirmation timed out"
        end
      end
      SnsMultipost::Poster::REGISTRY[name] = klass
      config = SnsMultipost::Config.new({ "dry_run" => false })
      queue = SnsMultipost::JobQueue.new(dir)
      queue.enqueue(SnsMultipost::Job.new(sns: name, text: "a"))

      SnsMultipost::Runner.new(config: config, queue: queue).run

      failed = JSON.parse(File.read(Dir[File.join(dir, "failed", "*.json")].first))
      assert_equal "unknown", failed["delivery_state"]
      assert_match(/DeliveryUnknownError/, failed["last_error"])
    ensure
      SnsMultipost::Poster::REGISTRY.delete(name)
    end
  end
end
