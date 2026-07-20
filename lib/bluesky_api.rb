# lib/bluesky_api.rb
require "net/http"
require "json"
require "uri"

module SnsMultipost
  class BlueskyApi
    BASE = "https://bsky.social".freeze

    DEFAULT_TRANSPORT = lambda do |req, base|
      Net::HTTP.start(base.host, base.port, use_ssl: base.scheme == "https") do |http|
        http.request(req)
      end
    end

    def initialize(handle:, app_password:, base_url: BASE, transport: DEFAULT_TRANSPORT)
      @base = URI(base_url)
      @handle = handle
      @app_password = app_password
      @transport = transport
      @jwt = nil
      @did = nil
    end

    def login
      res = post_json("/xrpc/com.atproto.server.createSession",
                      { identifier: @handle, password: @app_password }, auth: false)
      @jwt = res["accessJwt"]
      @did = res["did"]
      res
    end

    def upload_blob(path)
      login unless @jwt
      req = Net::HTTP::Post.new("/xrpc/com.atproto.repo.uploadBlob")
      req["Content-Type"] = mime_for(path)
      req.body = File.binread(path)
      request(req)["blob"]
    end

    def create_post(text, blobs: [], created_at:)
      login unless @jwt
      record = { "$type" => "app.bsky.feed.post", "text" => text, "createdAt" => created_at }
      unless blobs.empty?
        record["embed"] = {
          "$type" => "app.bsky.embed.images",
          "images" => blobs.map { |b| { "alt" => "", "image" => b } }
        }
      end
      post_json("/xrpc/com.atproto.repo.createRecord",
                { repo: @did, collection: "app.bsky.feed.post", record: record })
    end

    private

    def mime_for(path)
      case File.extname(path).downcase
      when ".png"  then "image/png"
      when ".gif"  then "image/gif"
      when ".webp" then "image/webp"
      else "image/jpeg"
      end
    end

    def post_json(path, hash, auth: true)
      req = Net::HTTP::Post.new(path)
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(hash)
      request(req, auth: auth)
    end

    def request(req, auth: true)
      req["Authorization"] = "Bearer #{@jwt}" if auth && @jwt
      res = @transport.call(req, @base)
      code = res.code.to_i
      unless code.between?(200, 299)
        raise "Bluesky API error #{res.code}: #{res.body.to_s[0, 200]}"
      end
      JSON.parse(res.body)
    end
  end
end
