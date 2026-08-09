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
        client.post(text: text, media_paths: paths)
      end

      private

      def client
        @client ||= Mixi2Browser.new
      end
    end

    register "mixi2", Mixi2
  end
end
