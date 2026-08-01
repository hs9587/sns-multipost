# lib/poster/tumblr.rb
require_relative "base"
require_relative "../tumblr_api"
require_relative "../tumblr_token"
require_relative "../token_store"
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
        id = res["response"]["id"].to_s
        { id: id, url: post_url(id) }
      end

      private

      def post_url(id)
        blog = @config["tumblr"]["blog_identifier"].to_s
        host = blog.include?(".") ? blog : "#{blog}.tumblr.com"
        "https://#{host}/post/#{id}"
      end

      def api
        @api ||= begin
          c = @config["tumblr"]
          store = TokenStore.new(
            File.expand_path("../../state/tumblr_token.json", __dir__))
          token = TumblrToken.new(c, store: store).access_token
          TumblrApi.new(access_token: token, blog_identifier: c["blog_identifier"])
        end
      end
    end

    register "tumblr", Tumblr
  end
end
