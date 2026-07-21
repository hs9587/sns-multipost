require "net/http"
require "json"
require "uri"

module SnsMultipost
  module OAuthRefresh
    DEFAULT_TRANSPORT = lambda do |req, base|
      Net::HTTP.start(base.host, base.port, use_ssl: base.scheme == "https") do |http|
        http.request(req)
      end
    end

    # refresh token で access token を更新して返す
    def self.access_token(token_uri:, client_id:, client_secret:, refresh_token:,
                          transport: DEFAULT_TRANSPORT)
      base = URI(token_uri)
      req = Net::HTTP::Post.new(base.request_uri)
      req.set_form_data(
        "client_id" => client_id,
        "client_secret" => client_secret,
        "refresh_token" => refresh_token,
        "grant_type" => "refresh_token")
      res = transport.call(req, base)
      code = res.code.to_i
      unless code.between?(200, 299)
        raise "OAuth refresh error #{res.code}: #{res.body.to_s[0, 200]}"
      end
      data = JSON.parse(res.body)
      data["access_token"] ||
        raise("OAuth refresh: no access_token in response: #{res.body.to_s[0, 200]}")
    end
  end
end
