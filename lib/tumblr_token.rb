# lib/tumblr_token.rb
require_relative "oauth_refresh"

module SnsMultipost
  class TumblrToken
    TOKEN_URI = "https://api.tumblr.com/v2/oauth2/token".freeze
    SKEW = 60 # 期限の何秒前を「切れた」とみなすか

    def initialize(config_tumblr, store:, refresher: OAuthRefresh, clock: -> { Time.now.to_i })
      @cfg = config_tumblr
      @store = store
      @refresher = refresher
      @clock = clock
    end

    def access_token
      data = @store.load
      if data["access_token"] && data["expires_at"] &&
         @clock.call < data["expires_at"].to_i - SKEW
        return data["access_token"]
      end
      refresh_token = data["refresh_token"] || @cfg["refresh_token"]
      res = @refresher.refresh(
        token_uri: TOKEN_URI,
        client_id: @cfg["client_id"], client_secret: @cfg["client_secret"],
        refresh_token: refresh_token)
      @store.save(
        "access_token" => res["access_token"],
        "refresh_token" => res["refresh_token"] || refresh_token,
        "expires_at" => @clock.call + (res["expires_in"] || 3600).to_i)
      res["access_token"]
    end
  end
end
