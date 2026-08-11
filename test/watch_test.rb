require_relative "test_helper"
require "watch"
require "config"
require "job_queue"
require "title_rules"
require "self_posted"

class WatchTest < Minitest::Test
  class FakeApi
    def initialize(statuses)
      @statuses = statuses
    end
    def statuses(account_id:, since_id: nil, max_id: nil, limit: 40, **_)
      result = @statuses
      result = result.select { |s| s["id"].to_i > since_id.to_i } if since_id
      result = result.select { |s| s["id"].to_i < max_id.to_i } if max_id
      result.first(limit)
    end
  end

  STATUSES = [
    { "id" => "5", "content" => "<p>パン食べた</p>", "url" => "u5", "media_attachments" => [] },
    { "id" => "4", "content" => "<p>自己投稿</p>", "url" => "u4", "media_attachments" => [] },
    { "id" => "3", "content" => "<p>返信です</p>", "in_reply_to_id" => "1",
      "url" => "u3", "media_attachments" => [] },
  ].freeze

  def build_watch(dir, statuses: STATUSES, targets: %w[x bluesky])
    sp = SnsMultipost::SelfPosted.new(File.join(dir, "sp.txt"))
    sp.record("4")
    queue = SnsMultipost::JobQueue.new(dir)
    watch = SnsMultipost::Watch.new(
      config: SnsMultipost::Config.new(
        { "targets" => { "watch" => targets },
          "fedibird" => { "account_id" => "42" } }),
      api: FakeApi.new(statuses),
      queue: queue,
      titles: SnsMultipost::TitleRules.load,
      self_posted: sp,
      state_path: File.join(dir, "since_id.txt"),
      media_root: File.join(dir, "media"),
      media_fetcher: ->(_u) { "" })
    [watch, queue]
  end

  def test_first_run_records_state_without_enqueue
    Dir.mktmpdir do |dir|
      watch, queue = build_watch(dir)
      assert_equal 0, watch.run
      assert_empty queue.pending
      assert_equal "5", File.read(File.join(dir, "since_id.txt"))
    end
  end

  def test_enqueues_new_statuses_skipping_reply_and_self_posted
    Dir.mktmpdir do |dir|
      watch, queue = build_watch(dir)
      File.write(File.join(dir, "since_id.txt"), "2")
      watch.run
      jobs = queue.pending
      assert_equal 2, jobs.size
      assert_equal %w[bluesky x], jobs.map(&:sns).sort
      assert jobs.all? { |j| j.text == "パン食べた" }
      assert jobs.all? { |j| j.title == "パン" }
      assert_equal "5", File.read(File.join(dir, "since_id.txt"))
    end
  end

  def test_sync_only_advances_state_without_enqueue
    Dir.mktmpdir do |dir|
      watch, queue = build_watch(dir)
      File.write(File.join(dir, "since_id.txt"), "2")
      # enqueue: false（基準合わせ）はキューを作らず since_id だけ前進させる
      assert_equal 0, watch.run(enqueue: false)
      assert_empty queue.pending
      assert_equal "5", File.read(File.join(dir, "since_id.txt"))
    end
  end

  def test_self_posted_status_is_not_requeued_but_advances_state
    Dir.mktmpdir do |dir|
      statuses = [
        { "id" => "4", "content" => "<p>bin/postからの投稿</p>",
          "url" => "u4", "media_attachments" => [] },
      ]
      watch, queue = build_watch(dir, statuses: statuses)
      File.write(File.join(dir, "since_id.txt"), "3")

      watch.run

      assert_empty queue.pending
      assert_equal "4", File.read(File.join(dir, "since_id.txt"))
    end
  end

  def test_rewind_moves_since_id_to_previous_status_without_enqueue
    Dir.mktmpdir do |dir|
      watch, queue = build_watch(dir)
      File.write(File.join(dir, "since_id.txt"), "5")

      result = watch.rewind(count: 1)

      assert_equal({ from: "5", to: "4", count: 1 }, result)
      assert_equal "4", File.read(File.join(dir, "since_id.txt"))
      assert_empty queue.pending
    end
  end

  def test_rewind_can_move_more_than_one_status
    Dir.mktmpdir do |dir|
      watch, = build_watch(dir)
      File.write(File.join(dir, "since_id.txt"), "5")

      watch.rewind(count: 2)

      assert_equal "3", File.read(File.join(dir, "since_id.txt"))
    end
  end

  def test_rewind_does_not_change_state_when_history_is_insufficient
    Dir.mktmpdir do |dir|
      watch, = build_watch(dir)
      state = File.join(dir, "since_id.txt")
      File.write(state, "3")

      error = assert_raises(RuntimeError) { watch.rewind(count: 1) }

      assert_match(/監視基準は変更しません/, error.message)
      assert_equal "3", File.read(state)
    end
  end

  def test_rewind_requires_existing_state
    Dir.mktmpdir do |dir|
      watch, = build_watch(dir)

      error = assert_raises(RuntimeError) { watch.rewind(count: 1) }

      assert_match(/--sync-only/, error.message)
    end
  end

  def test_threads_media_urls_into_jobs
    Dir.mktmpdir do |dir|
      statuses = [
        { "id" => "9", "content" => "<p>写真つき</p>", "url" => "u9",
          "media_attachments" => [{ "url" => "https://media.example/a.jpg" },
                                  { "url" => "https://media.example/b.jpg" }] },
      ]
      watch, queue = build_watch(dir, statuses: statuses, targets: %w[threads])
      File.write(File.join(dir, "since_id.txt"), "0")
      watch.run
      job = queue.pending.first
      assert_equal ["https://media.example/a.jpg", "https://media.example/b.jpg"],
                   job.media_urls
    end
  end
end
