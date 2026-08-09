require_relative "base"
require_relative "../jotter_browser"

module SnsMultipost
  module Poster
    class Jotter < Base
      def initialize(config, client: nil)
        super(config)
        @client = client
      end

      def perform(job)
        client.post(
          text: job.text.to_s,
          failure_screenshot_path: failure_screenshot_path(job))
      end

      private

      def failure_screenshot_path(job)
        return nil unless job.respond_to?(:path) && job.path

        root = File.dirname(File.dirname(job.path))
        basename = File.basename(job.path, File.extname(job.path))
        File.join(root, "failed", "#{basename}.png")
      end

      def client
        @client ||= begin
          settings = @config["jotter"] || {}
          JotterBrowser.new(
            savepoint_url: settings["savepoint_url"],
            account_name: settings["account_name"])
        end
      end
    end

    register "jotter", Jotter
  end
end
