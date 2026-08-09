require_relative "base"
require_relative "../media"
require_relative "../mixi2_browser"
require_relative "../text_limit"

module SnsMultipost
  module Poster
    class Mixi2 < Base
      def initialize(config, client: nil)
        super(config)
        @client = client
      end

      def perform(job)
        text = TextLimit.fit(job.text.to_s, "mixi2")
        paths = Media.for_sns(job.media_paths || [], "mixi2")
        client.post(
          text: text,
          media_paths: paths,
          failure_screenshot_path: failure_screenshot_path(job))
      end

      private

      def client
        @client ||= Mixi2Browser.new
      end

      def failure_screenshot_path(job)
        return nil unless job.respond_to?(:path) && job.path

        root = File.dirname(File.dirname(job.path))
        basename = File.basename(job.path, File.extname(job.path))
        File.join(root, "failed", "#{basename}.png")
      end
    end

    register "mixi2", Mixi2
  end
end
