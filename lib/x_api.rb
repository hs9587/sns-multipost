# lib/x_api.rb
require "net/http"
require "json"
require "uri"
require "securerandom"
require_relative "oauth1"

module SnsMultipost
  class XApi
    BASE = "https://api.twitter.com".freeze
    UPLOAD_BASE = "https://api.twitter.com".freeze

    DEFAULT_TRANSPORT = lambda do |req, base|
      Net::HTTP.start(base.host, base.port, use_ssl: base.scheme == "https") do |http|
        http.request(req)
      end
    end

    def initialize(consumer_key:, consumer_secret:, access_token:, access_token_secret:,
                   base_url: BASE, upload_base_url: UPLOAD_BASE,
                   transport: DEFAULT_TRANSPORT,
                   nonce_gen: -> { SecureRandom.hex(16) }, clock: -> { Time.now.to_i })
      @ck = consumer_key
      @cs = consumer_secret
      @token = access_token
      @token_secret = access_token_secret
      @base = URI(base_url)
      @upload_base = URI(upload_base_url)
      @transport = transport
      @nonce_gen = nonce_gen
      @clock = clock
    end

    def upload_media(path)
      boundary = "----SnsMultipost#{SecureRandom.hex(8)}"
      body = "".b
      body << "--#{boundary}\r\n".b
      body << "Content-Disposition: form-data; name=\"media_category\"\r\n\r\n".b
      body << "tweet_image\r\n".b
      body << "--#{boundary}\r\n".b
      body << "Content-Disposition: form-data; name=\"media\"; filename=\"#{File.basename(path)}\"\r\n".b
      body << "Content-Type: application/octet-stream\r\n\r\n".b
      body << File.binread(path)
      body << "\r\n--#{boundary}--\r\n".b
      full = "#{@upload_base}/2/media/upload"
      req = Net::HTTP::Post.new("/2/media/upload")
      req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      req["Authorization"] = sign("POST", full)
      req.body = body
      res = send_request(req, @upload_base)
      res.dig("data", "id") || res["media_id_string"] ||
        raise("X media upload: no media id in response")
    end

    def create_tweet(text, media_ids: [])
      payload = { "text" => text }
      payload["media"] = { "media_ids" => media_ids } unless media_ids.empty?
      full = "#{@base}/2/tweets"
      req = Net::HTTP::Post.new("/2/tweets")
      req["Content-Type"] = "application/json"
      req["Authorization"] = sign("POST", full)
      req.body = JSON.generate(payload)
      send_request(req, @base)
    end

    private

    def sign(method, full_url)
      OAuth1.authorization_header(
        method: method, url: full_url,
        consumer_key: @ck, consumer_secret: @cs,
        token: @token, token_secret: @token_secret,
        nonce: @nonce_gen.call, timestamp: @clock.call.to_s)
    end

    def send_request(req, base)
      res = @transport.call(req, base)
      code = res.code.to_i
      unless code.between?(200, 299)
        raise "X API error #{res.code}: #{res.body.to_s[0, 200]}"
      end
      JSON.parse(res.body)
    end
  end
end
