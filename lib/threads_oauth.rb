require "net/http"
require "json"
require "uri"

module SnsMultipost
  module ThreadsOAuth
    AUTHORIZE_URI = "https://threads.net/oauth/authorize".freeze
    API_BASE = "https://graph.threads.net".freeze

    DEFAULT_TRANSPORT = lambda do |req, base|
      Net::HTTP.start(base.host, base.port, use_ssl: base.scheme == "https") do |http|
        http.request(req)
      end
    end

    module_function

    def authorization_url(client_id:, redirect_uri:, state:)
      uri = URI(AUTHORIZE_URI)
      uri.query = URI.encode_www_form(
        "client_id" => client_id,
        "redirect_uri" => redirect_uri,
        "scope" => "threads_basic,threads_content_publish",
        "response_type" => "code",
        "state" => state)
      uri.to_s
    end

    def exchange_code(client_id:, client_secret:, redirect_uri:, code:,
                      transport: DEFAULT_TRANSPORT)
      base = URI(API_BASE)
      req = Net::HTTP::Post.new("/oauth/access_token")
      req.set_form_data(
        "client_id" => client_id,
        "client_secret" => client_secret,
        "redirect_uri" => redirect_uri,
        "code" => code,
        "grant_type" => "authorization_code")
      request(req, base, transport)
    end

    def exchange_long_lived(client_secret:, access_token:, transport: DEFAULT_TRANSPORT)
      get_token(
        "/access_token",
        { "grant_type" => "th_exchange_token",
          "client_secret" => client_secret,
          "access_token" => access_token },
        transport)
    end

    def refresh(access_token:, transport: DEFAULT_TRANSPORT)
      get_token(
        "/refresh_access_token",
        { "grant_type" => "th_refresh_token", "access_token" => access_token },
        transport)
    end

    def get_token(path, params, transport)
      base = URI(API_BASE)
      req = Net::HTTP::Get.new("#{path}?#{URI.encode_www_form(params)}")
      request(req, base, transport)
    end
    private_class_method :get_token

    def request(req, base, transport)
      res = transport.call(req, base)
      code = res.code.to_i
      unless code.between?(200, 299)
        raise "Threads OAuth error #{res.code}: #{res.body.to_s[0, 200]}"
      end
      JSON.parse(res.body)
    end
    private_class_method :request
  end
end
