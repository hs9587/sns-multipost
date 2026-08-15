require_relative "base"
require_relative "../jotter_browser"
require_relative "../media"
require_relative "../token_store"

module SnsMultipost
  module Poster
    class Jotter < Base
      def initialize(config, client: nil)
        super(config)
        @client = client
      end

      def perform(job)
        paths = Media.for_sns(job.media_paths || [], "jotter")
        client.post(
          text: job.text.to_s,
          media_paths: paths,
          expected_browser_id_fingerprint: paths.empty? ? nil : wallet_fingerprint,
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

      def wallet_fingerprint
        path = File.expand_path("../../state/jotter_wallet.json", __dir__)
        TokenStore.new(path).load["browser_id_fingerprint"].to_s
      end
    end

    register "jotter", Jotter
  end
end
