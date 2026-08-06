require "net/http"
require "json"
require "uri"

module SnsMultipost
  class ThreadsApi
    BASE = "https://graph.threads.net".freeze

    DEFAULT_TRANSPORT = lambda do |req, base|
      Net::HTTP.start(base.host, base.port, use_ssl: base.scheme == "https") do |http|
        http.request(req)
      end
    end

    def initialize(access_token:, base_url: BASE, transport: DEFAULT_TRANSPORT)
      @base = URI(base_url)
      @token = access_token
      @transport = transport
    end

    def create_text_post(text)
      req = Net::HTTP::Post.new("/me/threads")
      req.set_form_data(
        "media_type" => "TEXT",
        "text" => text,
        "auto_publish_text" => "true")
      request(req)
    end

    private

    def request(req)
      req["Authorization"] = "Bearer #{@token}"
      res = @transport.call(req, @base)
      code = res.code.to_i
      unless code.between?(200, 299)
        raise "Threads API error #{res.code}: #{res.body.to_s[0, 200]}"
      end
      JSON.parse(res.body)
    end
  end
end
