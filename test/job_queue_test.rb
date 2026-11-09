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

  def test_confirmed_requeue_clears_unknown_delivery_state
    Dir.mktmpdir do |dir|
      q = SnsMultipost::JobQueue.new(dir)
      q.enqueue(SnsMultipost::Job.new(
        sns: "jotter", text: "t", delivery_state: "unknown"))
      job = q.pending.first
      q.fail(job, "confirmation failed")
      failed = Dir[File.join(dir, "failed", "*.json")].first

      q.requeue(failed, confirmed_not_delivered: true)

      assert_nil q.pending.first.delivery_state
    end
  end

  def test_deferred_job_is_hidden_until_retry_time
    Dir.mktmpdir do |dir|
      queue = SnsMultipost::JobQueue.new(dir)
      queue.enqueue(SnsMultipost::Job.new(sns: "jotter", text: "t"))
      job = queue.pending.first
      retry_after = Time.new(2026, 11, 10, 6, 20, 0, "+09:00")

      queue.defer(job, "temporary", retry_after: retry_after)

      assert_empty queue.pending(now: retry_after - 1)
      assert_equal [File.basename(job.path)],
                   queue.deferred(now: retry_after - 1).map { |item| File.basename(item.path) }
      assert_equal 1, queue.pending(now: retry_after).size
      stored = JSON.parse(File.read(job.path))
      assert_equal 1, stored["attempts"]
      assert_equal retry_after.iso8601, stored["retry_after"]
    end
  end

  def test_resolve_as_posted_moves_unknown_job_to_done_without_queueing
    Dir.mktmpdir do |dir|
      queue = SnsMultipost::JobQueue.new(dir)
      queue.enqueue(SnsMultipost::Job.new(
        sns: "jotter", text: "t", delivery_state: "unknown"))
      job = queue.pending.first
      queue.fail(job, "confirmation failed")
      failed = Dir[File.join(dir, "failed", "*.json")].first

      destination = queue.resolve_as_posted(failed)

      assert_equal File.join(dir, "done", File.basename(failed)), destination
      assert_empty queue.pending
      data = JSON.parse(File.read(destination))
      assert_equal "confirmed_posted", data["delivery_state"]
    end
  end

  def test_enqueue_reuses_job_with_same_dedupe_key_after_completion
    Dir.mktmpdir do |dir|
      queue = SnsMultipost::JobQueue.new(dir)
      first = SnsMultipost::Job.new(
        sns: "bluesky", text: "t", dedupe_key: "batch:9:bluesky")
      first_path = queue.enqueue(first, now: Time.new(2026, 9, 6, 10, 0, 0))
      queue.complete(queue.pending.first)

      second_path = queue.enqueue(SnsMultipost::Job.new(
        sns: "bluesky", text: "t", dedupe_key: "batch:9:bluesky"),
        now: Time.new(2026, 9, 6, 10, 1, 0))

      assert_equal File.join(dir, "done", File.basename(first_path)), second_path
      assert_empty queue.pending
      assert_equal 1, Dir[File.join(dir, "done", "*.json")].length
    end
  end
end
