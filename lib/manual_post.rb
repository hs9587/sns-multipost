require_relative "html_text"

module SnsMultipost
  module ManualPost
    LOCAL_IMAGE_TARGETS = %w[fedibird bluesky tumblr mixi mixi2].freeze
    PUBLIC_IMAGE_TARGETS = %w[threads blogger].freeze

    def self.resolve_image_paths(paths, base_dir: Dir.pwd)
      Array(paths).map do |path|
        absolute = File.expand_path(path.to_s, base_dir)
        raise ArgumentError, "画像ファイルが見つかりません: #{path}" unless File.file?(absolute)

        absolute
      end
    end

    def self.select_targets(configured:, targets:, mode: nil)
      requested = Array(targets)
      requested = Array(configured) if requested.empty?
      requested = requested.uniq
      return [requested, []] unless mode

      allowed, option =
        case mode
        when :local_images
          [LOCAL_IMAGE_TARGETS, "--image"]
        when :fedibird_latest
          [PUBLIC_IMAGE_TARGETS, "--from-fedibird-latest"]
        else
          raise ArgumentError, "不明な手動投稿モードです: #{mode}"
        end
      selected = requested.select { |sns| allowed.include?(sns) }
      skipped = requested - selected
      if selected.empty?
        supported = allowed.join(", ")
        raise ArgumentError, "#{option}を利用できる投稿先がありません（対応: #{supported}）"
      end
      [selected, skipped]
    end

    def self.latest_fedibird_source(api:, account_id:)
      status = api.statuses(account_id: account_id, limit: 1).first
      raise ArgumentError, "Fedibirdの最新投稿を取得できません" unless status

      media_urls = Array(status["media_attachments"]).filter_map do |attachment|
        type = attachment["type"].to_s
        next unless type.empty? || type == "image"

        url = attachment["url"].to_s
        url unless url.empty?
      end
      raise ArgumentError, "Fedibirdの最新投稿に画像がありません: #{status['url']}" if media_urls.empty?

      text = HtmlText.to_text(status["content"].to_s)
      raise ArgumentError, "Fedibirdの最新投稿に本文がありません: #{status['url']}" if text.empty?

      { text: text, media_urls: media_urls, source_url: status["url"].to_s }
    end
  end
end
