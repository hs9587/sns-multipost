require "json"
require "fileutils"
require "pathname"
require "time"

module SnsMultipost
  class Cleanup
    Item = Struct.new(:path, :bytes, :updated_at, keyword_init: true)
    Report = Struct.new(
      :cutoff, :done, :orphan_screenshots, :media, :browser_cache,
      :warnings, :protected_failed_jobs, :protected_media, keyword_init: true)
    ApplyResult = Struct.new(:removed, :failed, :skipped_browser_cache, keyword_init: true)

    CACHE_NAMES = [
      "cache", "code cache", "gpucache", "grshadercache", "shadercache",
      "graphitedawncache", "dawngraphitecache", "dawnwebgpucache",
      "browsermetrics"
    ].freeze

    def initialize(root: File.expand_path("..", __dir__), now: Time.now)
      @root = File.expand_path(root)
      @now = now
    end

    def scan(days: 30)
      cutoff = @now - Integer(days) * 86_400
      warnings = []
      references, readable = pending_media_references(warnings)
      media_items, protected_media = media_candidates(cutoff, references, readable)
      Report.new(
        cutoff: cutoff,
        done: old_files("done", "*.json", cutoff),
        orphan_screenshots: orphan_screenshot_candidates(cutoff),
        media: media_items,
        browser_cache: browser_cache_candidates,
        warnings: warnings,
        protected_failed_jobs: files("failed", "*.json").length,
        protected_media: protected_media)
    end

    def apply(report, include_browser_cache: false)
      removed = []
      failed = []
      items = report.done + report.orphan_screenshots + report.media
      items += report.browser_cache if include_browser_cache

      items.each do |entry|
        path = cleanup_path(entry.path)
        next unless File.exist?(path) || File.symlink?(path)

        if File.directory?(path) && !File.symlink?(path)
          FileUtils.remove_entry_secure(path)
        else
          File.delete(path)
        end
        removed << entry
      rescue StandardError => e
        failed << [entry, e]
      end

      ApplyResult.new(
        removed: removed,
        failed: failed,
        skipped_browser_cache: include_browser_cache ? [] : report.browser_cache)
    end

    def self.format(report, limit: 10)
      lines = [
        "cleanup dry-run（削除は行いません）",
        "経過日数の基準: #{report.cutoff.getlocal.strftime('%Y年%-m月%-d日 %H:%M:%S')}以前"
      ]
      append_section(lines, "古い完了ジョブ", report.done, limit)
      append_section(lines, "対応JSONのない失敗スクリーンショット",
                     report.orphan_screenshots, limit)
      append_section(lines, "未処理ジョブから参照されない古い画像", report.media, limit)
      append_section(lines, "再生成可能なChromeキャッシュ（経過日数の対象外）",
                     report.browser_cache, limit)
      total_items = [report.done, report.orphan_screenshots,
                     report.media, report.browser_cache].flatten
      lines << "候補合計: #{total_items.length}件 #{format_bytes(total_items.sum(&:bytes))}"
      lines << "保護: failed JSON #{report.protected_failed_jobs}件、参照中media #{report.protected_media}件"
      lines << "保護: ChromeのCookie・Local Storage・IndexedDB・Service Worker・ログイン情報"
      report.warnings.each { |warning| lines << "警告: #{warning}" }
      lines << "一覧は候補確認だけです。Chromeプロファイルを清掃する場合は専用Chromeをすべて閉じる必要があります。"
      lines.join("\n")
    end

    def self.format_apply(result)
      lines = [
        "cleanup apply",
        "削除完了: #{result.removed.length}件 #{format_bytes(result.removed.sum(&:bytes))}"
      ]
      unless result.skipped_browser_cache.empty?
        lines << "Chromeキャッシュは未削除: #{result.skipped_browser_cache.length}件 " \
                 "#{format_bytes(result.skipped_browser_cache.sum(&:bytes))}"
        lines << "削除する場合は専用Chromeをすべて閉じ、--include-browser-cacheを追加してください。"
      end
      result.failed.each do |entry, error|
        lines << "削除失敗: #{entry.path.tr('\\', '/')}（#{error.class}: #{error.message}）"
      end
      lines << "失敗: #{result.failed.length}件"
      lines.join("\n")
    end

    def self.append_section(lines, label, items, limit)
      lines << "#{label}: #{items.length}件 #{format_bytes(items.sum(&:bytes))}"
      items.first(limit).each do |item|
        relative = item.path.tr("\\", "/")
        lines << "  #{relative} (#{format_bytes(item.bytes)})"
      end
      remaining = items.length - limit
      lines << "  ほか#{remaining}件" if remaining.positive?
    end
    private_class_method :append_section

    def self.format_bytes(bytes)
      return "#{bytes} B" if bytes < 1024
      return Kernel.format("%.2f KiB", bytes / 1024.0) if bytes < 1024 * 1024

      Kernel.format("%.2f MiB", bytes / 1024.0 / 1024.0)
    end
    private_class_method :format_bytes

    private

    def cleanup_path(relative_path)
      relative = Pathname.new(relative_path.to_s)
      raise ArgumentError, "絶対パスは削除対象にできません" if relative.absolute?

      path = File.expand_path(relative.to_s, @root)
      root_prefix = @root.end_with?(File::SEPARATOR) ? @root : "#{@root}#{File::SEPARATOR}"
      unless path.start_with?(root_prefix) && allowed_cleanup_path?(path)
        raise ArgumentError, "許可されていない削除対象です: #{relative_path}"
      end
      path
    end

    def allowed_cleanup_path?(path)
      relative = Pathname.new(path).relative_path_from(Pathname.new(@root)).each_filename.to_a
      direct_json = relative.length == 2 && relative.first == "done" &&
                    relative.last.end_with?(".json")
      direct_png = relative.length == 2 && relative.first == "failed" &&
                   relative.last.end_with?(".png")
      direct_json || direct_png || media_directory?(relative) ||
        browser_cache_directory?(relative)
    end

    def media_directory?(parts)
      parts.length == 3 && parts[0, 2] == ["state", "media"]
    end

    def browser_cache_directory?(parts)
      parts.length >= 4 && parts[0, 2] == ["state", "browser"] &&
        CACHE_NAMES.include?(parts.last.downcase) &&
        parts.none? { |part| part.casecmp?("Storage") }
    end

    def files(directory, pattern)
      Dir.glob(File.join(directory, pattern), base: @root)
         .map { |path| File.join(@root, path) }
         .select { |path| File.file?(path) }
    end

    def old_files(directory, pattern, cutoff)
      files(directory, pattern).filter_map do |path|
        item(path) if File.mtime(path) <= cutoff
      end.sort_by(&:updated_at)
    end

    def orphan_screenshot_candidates(cutoff)
      json_bases = files("failed", "*.json").to_h do |path|
        [File.basename(path, ".json"), true]
      end
      files("failed", "*.png").filter_map do |path|
        next if json_bases[File.basename(path, ".png")]
        item(path) if File.mtime(path) <= cutoff
      end.sort_by(&:updated_at)
    end

    def pending_media_references(warnings)
      references = {}
      paths = files("queue", "*.json") + files("failed", "*.json")
      paths.each do |path|
        Array(JSON.parse(File.read(path))["media_paths"]).each do |media_path|
          references[File.expand_path(File.dirname(media_path))] = true
        end
      rescue JSON::ParserError, Errno::ENOENT => e
        warnings << "#{relative(path)}を読めないためmedia候補を表示しません（#{e.class}）"
        return [{}, false]
      end
      [references, true]
    end

    def media_candidates(cutoff, references, readable)
      directories = Dir.glob(File.join("state", "media", "*"), base: @root)
                    .map { |path| File.join(@root, path) }
                    .select { |path| File.directory?(path) }
      protected_count = directories.count { |path| references[File.expand_path(path)] }
      return [[], protected_count] unless readable

      candidates = directories.filter_map do |path|
        next if references[File.expand_path(path)]
        candidate = directory_item(path)
        candidate if candidate.updated_at <= cutoff
      end.sort_by(&:updated_at)
      [candidates, protected_count]
    end

    def browser_cache_candidates
      browser_root = File.join(@root, "state", "browser")
      return [] unless File.directory?(browser_root)

      candidates = Dir.glob(File.join("state", "browser", "**", "*"), base: @root)
                      .map { |path| File.join(@root, path) }.select do |path|
        File.directory?(path) && CACHE_NAMES.include?(File.basename(path).downcase) &&
          !storage_path?(path)
      end.sort_by(&:length)
      roots = candidates.reject do |path|
        candidates.any? { |parent| parent != path && descendant?(path, parent) }
      end
      roots.map { |path| directory_item(path) }.sort_by { |entry| -entry.bytes }
    end

    def storage_path?(path)
      Pathname.new(path).each_filename.any? { |part| part.casecmp?("Storage") }
    end

    def descendant?(path, parent)
      Pathname.new(path).ascend.any? { |ancestor| ancestor.to_s == parent }
    end

    def directory_item(path)
      base = relative(path)
      entries = Dir.glob(File.join(base, "**", "*"), base: @root)
                   .map { |entry| File.join(@root, entry) }
                   .select { |entry| File.file?(entry) }
      updated = entries.map { |entry| File.mtime(entry) }.max || File.mtime(path)
      Item.new(path: relative(path), bytes: entries.sum { |entry| File.size(entry) },
               updated_at: updated)
    end

    def item(path)
      Item.new(path: relative(path), bytes: File.size(path), updated_at: File.mtime(path))
    end

    def relative(path)
      Pathname.new(File.expand_path(path)).relative_path_from(Pathname.new(@root)).to_s
    end
  end
end
