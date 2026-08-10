module SnsMultipost
  module ManualPost
    LOCAL_IMAGE_TARGETS = %w[bluesky tumblr mixi mixi2].freeze

    def self.resolve_image_paths(paths, base_dir: Dir.pwd)
      Array(paths).map do |path|
        absolute = File.expand_path(path.to_s, base_dir)
        raise ArgumentError, "画像ファイルが見つかりません: #{path}" unless File.file?(absolute)

        absolute
      end
    end

    def self.select_targets(configured:, target:, with_images:)
      requested = target ? [target] : Array(configured)
      return [requested, []] unless with_images

      selected = requested.select { |sns| LOCAL_IMAGE_TARGETS.include?(sns) }
      skipped = requested - selected
      if selected.empty?
        supported = LOCAL_IMAGE_TARGETS.join(", ")
        raise ArgumentError, "--imageを利用できる投稿先がありません（対応: #{supported}）"
      end
      [selected, skipped]
    end
  end
end
