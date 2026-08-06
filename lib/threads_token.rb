require_relative "threads_oauth"

module SnsMultipost
  class ThreadsToken
    SKEW = 7 * 24 * 60 * 60
    DEFAULT_EXPIRES_IN = 60 * 24 * 60 * 60

    def initialize(config_threads, store:, refresher: ThreadsOAuth, clock: -> { Time.now.to_i })
      @cfg = config_threads || {}
      @store = store
      @refresher = refresher
      @clock = clock
    end

    def access_token
      data = @store.load
      token = data["access_token"].to_s
      if !token.empty?
        expires_at = data["expires_at"]
        return token unless expires_at
        return token if @clock.call < expires_at.to_i - SKEW

        return refresh(token, data)
      end

      configured = @cfg["access_token"].to_s
      return configured unless configured.empty?

      raise "Threads access token がありません。ruby bin/threads_auth --authorize から認証してください"
    end

    private

    def refresh(token, data)
      res = @refresher.refresh(access_token: token)
      new_token = res["access_token"].to_s
      raise "Threads token refresh: no access_token in response" if new_token.empty?

      @store.save(
        data.merge(
          "access_token" => new_token,
          "expires_at" => @clock.call +
            (res["expires_in"] || DEFAULT_EXPIRES_IN).to_i))
      new_token
    end
  end
end
