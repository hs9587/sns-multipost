require "time"
require_relative "base"
require_relative "../bluesky_api"
require_relative "../media"
require_relative "../text_limit"

module SnsMultipost
  module Poster
    class Bluesky < Base
      def initialize(config, api: nil, clock: -> { Time.now.utc }, logger: ->(m) { warn m })
        super(config)
        @api = api
        @clock = clock
        @logger = logger
      end

      def perform(job)
        paths = Media.within_size(Media.for_sns(job.media_paths, "bluesky"), "bluesky",
                                  logger: @logger)
        blobs = paths.map { |p| api.upload_blob(p) }
        text = TextLimit.fit(job.text.to_s, "bluesky")
        res = api.create_post(text, blobs: blobs, created_at: @clock.call.iso8601)
        { uri: res["uri"], url: post_url(res["uri"]) }
      end

      private

      def post_url(uri)
        rkey = uri.to_s.split("/").last
        "https://bsky.app/profile/#{@config["bluesky"]["handle"]}/post/#{rkey}"
      end

      def api
        @api ||= BlueskyApi.new(
          handle: @config["bluesky"]["handle"],
          app_password: @config["bluesky"]["app_password"])
      end
    end

    register "bluesky", Bluesky
  end
end
