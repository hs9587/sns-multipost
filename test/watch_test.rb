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
    def statuses(account_id:, since_id: nil, **_)
      since_id ? @statuses.select { |s| s["id"].to_i > since_id.to_i } : @statuses
    end
  end

  STATUSES = [
    { "id" => "5", "content" => "<p>パン食べた</p>", "url" => "u5", "media_attachments" => [] },
    { "id" => "4", "content" => "<p>自己投稿</p>", "url" => "u4", "media_attachments" => [] },
    { "id" => "3", "content" => "<p>返信です</p>", "in_reply_to_id" => "1",
      "url" => "u3", "media_attachments" => [] },
  ].freeze

  def build_watch(dir, statuses: STATUSES, targets: %w[fedibird x bluesky])
    sp = SnsMultipost::SelfPosted.new(File.join(dir, "sp.txt"))
    sp.record("4")
    queue = SnsMultipost::JobQueue.new(dir)
    watch = SnsMultipost::Watch.new(
      config: SnsMultipost::Config.new(
        { "targets" => targets, "fedibird" => { "account_id" => "42" } }),
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
end
