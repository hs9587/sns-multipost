require_relative "base"
require_relative "../x_api"
require_relative "../media"
require_relative "../text_limit"

module SnsMultipost
  module Poster
    class X < Base
      def initialize(config, api: nil, logger: ->(m) { warn m })
        super(config)
        @api = api
        @logger = logger
      end

      def perform(job)
        paths = Media.within_size(Media.for_sns(job.media_paths, "x"), "x", logger: @logger)
        media_ids = paths.map { |p| api.upload_media(p) }
        text = TextLimit.fit(job.text.to_s, "x")
        res = api.create_tweet(text, media_ids: media_ids)
        id = res["data"]["id"].to_s
        { id: id, url: post_url(id) }
      end

      private

      def post_url(id)
        "https://x.com/#{@config["x"]["username"]}/status/#{id}"
      end

      def api
        @api ||= XApi.new(
          consumer_key: @config["x"]["consumer_key"],
          consumer_secret: @config["x"]["consumer_secret"],
          access_token: @config["x"]["access_token"],
          access_token_secret: @config["x"]["access_token_secret"])
      end
    end

    register "x", X
  end
end
