require_relative "test_helper"
require "cleanup"
require "json"

class CleanupTest < Minitest::Test
  NOW = Time.new(2026, 9, 6, 12, 0, 0, "+09:00")
  OLD = NOW - 40 * 86_400
  NEW = NOW - 2 * 86_400

  def test_scan_protects_pending_media_and_browser_state
    Dir.mktmpdir do |root|
      make_directories(root)
      old_done = write(root, "done/old.json", "{}", OLD)
      write(root, "done/new.json", "{}", NEW)
      orphan = write(root, "failed/orphan.png", "png", OLD)
      write(root, "failed/kept.json", JSON.generate(
        "media_paths" => [File.join(root, "state/media/used/01.png")]), OLD)
      write(root, "failed/kept.png", "png", OLD)
      write(root, "state/media/used/01.png", "used", OLD)
      unused = write(root, "state/media/unused/01.png", "unused", OLD)
      cache = write(root, "state/browser/mixi/Default/Cache/data", "cache", NEW)
      write(root, "state/browser/jotter/Default/IndexedDB/secret", "wallet", OLD)
      write(root, "state/browser/mixi/Default/Storage/ext/Cache/data", "extension", OLD)

      report = SnsMultipost::Cleanup.new(root: root, now: NOW).scan(days: 30)

      assert_equal [relative(root, old_done)], report.done.map(&:path)
      assert_equal [relative(root, orphan)], report.orphan_screenshots.map(&:path)
      assert_equal [relative(root, File.dirname(unused))], report.media.map(&:path)
      assert_equal [relative(root, File.dirname(cache))], report.browser_cache.map(&:path)
      assert_equal 1, report.protected_failed_jobs
      assert_equal 1, report.protected_media
      assert_empty report.warnings
    end
  end

  def test_unreadable_failed_json_disables_media_candidates_conservatively
    Dir.mktmpdir do |root|
      make_directories(root)
      write(root, "failed/broken.json", "{", OLD)
      write(root, "state/media/unused/01.png", "unused", OLD)

      report = SnsMultipost::Cleanup.new(root: root, now: NOW).scan(days: 30)

      assert_empty report.media
      assert_equal 1, report.warnings.length
      assert_match(/media候補を表示しません/, report.warnings.first)
    end
  end

  def test_format_limits_each_section_without_changing_totals
    report = SnsMultipost::Cleanup::Report.new(
      cutoff: OLD,
      done: 2.times.map { |i| item("done/#{i}.json", 1024) },
      orphan_screenshots: [], media: [], browser_cache: [], warnings: [],
      protected_failed_jobs: 3, protected_media: 1)

      output = SnsMultipost::Cleanup.format(report, limit: 1)

      assert_includes output, "cleanup dry-run（削除は行いません）"
      assert_includes output, "古い完了ジョブ: 2件 2.00 KiB"
      assert_includes output, "ほか1件"
      assert_includes output, "候補合計: 2件 2.00 KiB"
      assert_includes output, "failed JSON 3件、参照中media 1件"
  end

  private

  def make_directories(root)
    %w[queue done failed state/media state/browser].each do |path|
      FileUtils.mkdir_p(File.join(root, path))
    end
  end

  def write(root, path, content, time)
    full = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.binwrite(full, content)
    File.utime(time, time, full)
    full
  end

  def relative(root, path)
    Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
  end

  def item(path, bytes)
    SnsMultipost::Cleanup::Item.new(path: path, bytes: bytes, updated_at: OLD)
  end
end
