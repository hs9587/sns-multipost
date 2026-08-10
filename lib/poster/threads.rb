require_relative "base"
require_relative "../threads_api"
require_relative "../threads_token"
require_relative "../token_store"
require_relative "../text_limit"
require_relative "../media"

module SnsMultipost
  module Poster
    class Threads < Base
      def initialize(config, api: nil)
        super(config)
        @api = api
      end

      def perform(job)
        text = TextLimit.fit(job.text.to_s, "threads")
        urls = Array(job.media_urls).compact.reject(&:empty?).first(Media.limit_for("threads"))
        res =
          case urls.length
          when 0
            api.create_text_post(text)
          when 1
            api.create_image_post(text: text, image_url: urls.first)
          else
            api.create_carousel_post(text: text, image_urls: urls)
          end
        id = res["id"].to_s
        raise "Threads API response に投稿IDがありません" if id.empty?
        { id: id }
      end

      private

      def api
        @api ||= begin
          store = TokenStore.new(
            File.expand_path("../../state/threads_token.json", __dir__))
          token = ThreadsToken.new(@config["threads"], store: store).access_token
          ThreadsApi.new(access_token: token)
        end
      end
    end

    register "threads", Threads
  end
end
