require_relative "base"
require_relative "../fedibird_api"
require_relative "../media"
require_relative "../self_posted"

module SnsMultipost
  module Poster
    class Fedibird < Base
      def initialize(config, api: nil, self_posted: nil)
        super(config)
        @api = api
        @self_posted = self_posted || SelfPosted.new
      end

      def perform(job)
        media_ids = Media.for_sns(job.media_paths, "fedibird").map do |path|
          api.upload_media(path)["id"]
        end
        status = api.post_status(job.text, media_ids: media_ids)
        @self_posted.record(status["id"])
        { id: status["id"], url: status["url"] }
      end

      private

      def api
        @api ||= FedibirdApi.new(
          base_url: @config["fedibird"]["base_url"],
          access_token: @config["fedibird"]["access_token"])
      end
    end

    register "fedibird", Fedibird
  end
end
