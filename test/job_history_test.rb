require_relative "test_helper"
require "job_history"
require "fileutils"

class JobHistoryTest < Minitest::Test
  def test_selects_failed_jobs_at_or_after_latest_done_timestamp
    with_history do |done, failed|
      touch(done, "20260830-115702_tumblr_c438.json")
      touch(done, "20260830-115702_mixi_8269.json")
      touch(failed, "20260830-115702_jotter_e05d.json")
      touch(failed, "20260830-120000_mixi_abcd.json")
      touch(failed, "20260829-092702_jotter_be81.json")
      touch(failed, "20260830-120000_mixi_abcd.png")

      history = SnsMultipost::JobHistory.snapshot(
        done_directory: done, failed_directory: failed)

      assert_equal "20260830-115702", history[:latest_done_timestamp]
      assert_equal %w[20260830-120000_mixi_abcd.json 20260830-115702_jotter_e05d.json],
                   history[:failed_jobs]
      assert_equal 3, history[:all_failed_count]
    end
  end

  def test_all_includes_failed_jobs_older_than_latest_done
    with_history do |done, failed|
      touch(done, "20260830-115702_tumblr_c438.json")
      touch(failed, "20260829-092702_jotter_be81.json")

      history = SnsMultipost::JobHistory.snapshot(
        done_directory: done, failed_directory: failed, include_all: true)

      assert_equal ["20260829-092702_jotter_be81.json"], history[:failed_jobs]
      assert history[:include_all]
    end
  end

  def test_summary_and_list_formatting
    history = {
      latest_done: "20260830-115702_tumblr_c438.json",
      latest_done_timestamp: "20260830-115702",
      failed_jobs: %w[new.json middle.json old.json oldest.json],
      all_failed_count: 4,
      include_all: true
    }

    summary = SnsMultipost::JobHistory.format_summary(history, limit: 3)
    assert_includes summary, "done最新時刻: 2026年8月30日 11:57:02"
    assert_includes summary, "done最新と同時刻以降のfailed: 4件"
    assert_includes summary, "ほか1件"

    list = SnsMultipost::JobHistory.format_list(history, offset: 1, limit: 2)
    assert_includes list, "done最新ジョブ: 20260830-115702_tumblr_c438.json"
    assert_includes list, "表示: 2～3件目 / 4件"
    assert_includes list, "middle.json"
    assert_includes list, "old.json"
    refute_includes list, "new.json"
  end

  def test_labels_unknown_delivery_without_exposing_job_contents
    with_history do |done, failed|
      touch(done, "20260906-120000_tumblr_abcd.json")
      name = "20260906-120000_jotter_ef12.json"
      File.write(File.join(failed, name), JSON.generate(
        "delivery_state" => "unknown", "text" => "秘密ではないが表示しない本文"))

      history = SnsMultipost::JobHistory.snapshot(
        done_directory: done, failed_directory: failed)
      summary = SnsMultipost::JobHistory.format_summary(history)

      assert_includes summary, "#{name} [投稿結果不明]"
      refute_includes summary, "表示しない本文"
    end
  end

  private

  def with_history
    Dir.mktmpdir do |root|
      done = File.join(root, "done")
      failed = File.join(root, "failed")
      FileUtils.mkdir_p([done, failed])
      yield done, failed
    end
  end

  def touch(directory, name)
    FileUtils.touch(File.join(directory, name))
  end
end
