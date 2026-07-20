# lib/poster/tumblr.rb
require_relative "base"
require_relative "../tumblr_api"
require_relative "../media"

module SnsMultipost
  module Poster
    class Tumblr < Base
      def initialize(config, api: nil, logger: ->(m) { warn m })
        super(config)
        @api = api
        @logger = logger
      end

      def perform(job)
        paths = Media.within_size(Media.for_sns(job.media_paths, "tumblr"), "tumblr",
                                  logger: @logger)
        res = api.create_post(job.text.to_s, image_paths: paths)
        id = res["response"]["id_string"]
        { id: id, url: post_url(id) }
      end

      private

      def post_url(id)
        blog = @config["tumblr"]["blog_identifier"].to_s
        host = blog.include?(".") ? blog : "#{blog}.tumblr.com"
        "https://#{host}/post/#{id}"
      end

      def api
        @api ||= TumblrApi.new(
          access_token: @config["tumblr"]["access_token"],
          blog_identifier: @config["tumblr"]["blog_identifier"])
      end
    end

    register "tumblr", Tumblr
  end
end
