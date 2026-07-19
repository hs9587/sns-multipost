require_relative "test_helper"
require "job_queue"

class JobQueueTest < Minitest::Test
  def test_enqueue_and_complete
    Dir.mktmpdir do |dir|
      q = SnsMultipost::JobQueue.new(dir)
      job = SnsMultipost::Job.new(sns: "fedibird", text: "テスト本文", title: "テスト")
      path = q.enqueue(job, now: Time.new(2026, 7, 19, 21, 0, 0))
      assert_match(/20260719-210000_fedibird_\h{4}\.json\z/, File.basename(path))

      pending = q.pending
      assert_equal 1, pending.size
      assert_equal "テスト本文", pending.first.text

      q.complete(pending.first)
      assert_empty q.pending
      assert_equal 1, Dir[File.join(dir, "done", "*.json")].size
    end
  end

  def test_fail_records_error_and_requeue
    Dir.mktmpdir do |dir|
      q = SnsMultipost::JobQueue.new(dir)
      q.enqueue(SnsMultipost::Job.new(sns: "x", text: "t"))
      job = q.pending.first
      q.fail(job, "boom")

      failed = Dir[File.join(dir, "failed", "*.json")].first
      data = JSON.parse(File.read(failed))
      assert_equal 1, data["attempts"]
      assert_equal "boom", data["last_error"]

      q.requeue(failed)
      assert_equal 1, q.pending.size
      assert_empty Dir[File.join(dir, "failed", "*.json")]
    end
  end
end
