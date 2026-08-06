require_relative "base"
require_relative "../threads_api"
require_relative "../threads_token"
require_relative "../token_store"
require_relative "../text_limit"

module SnsMultipost
  module Poster
    class Threads < Base
      def initialize(config, api: nil)
        super(config)
        @api = api
      end

      def perform(job)
        text = TextLimit.fit(job.text.to_s, "threads")
        res = api.create_text_post(text)
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
