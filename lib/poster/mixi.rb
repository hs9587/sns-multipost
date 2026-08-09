require_relative "base"
require_relative "../media"
require_relative "../mixi_browser"
require_relative "../text_limit"

module SnsMultipost
  module Poster
    class Mixi < Base
      MAX_IMAGE_BYTES = 5_000_000
      IMAGE_EXTENSIONS = %w[.jpg .jpeg .png].freeze

      def initialize(config, client: nil)
        super(config)
        @client = client
      end

      def perform(job)
        text = TextLimit.fit(job.text.to_s, "mixi")
        paths = Media.for_sns(job.media_paths || [], "mixi")
        validate_media!(paths.first) unless paths.empty?
        client.post(
          text: text,
          media_paths: paths,
          failure_screenshot_path: failure_screenshot_path(job))
      end

      private

      def validate_media!(path)
        extension = File.extname(path).downcase
        raise "mixiはJPEGまたはPNG画像に対応しています: #{path}" unless IMAGE_EXTENSIONS.include?(extension)
        raise "mixiの画像は5MB以下にしてください: #{path}" if File.size(path) > MAX_IMAGE_BYTES
      end

      def failure_screenshot_path(job)
        return nil unless job.respond_to?(:path) && job.path

        root = File.dirname(File.dirname(job.path))
        basename = File.basename(job.path, File.extname(job.path))
        File.join(root, "failed", "#{basename}.png")
      end

      def client
        @client ||= MixiBrowser.new
      end
    end

    register "mixi", Mixi
  end
end
