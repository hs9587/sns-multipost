# lib/tumblr_api.rb
require "net/http"
require "json"
require "uri"
require "securerandom"

module SnsMultipost
  class TumblrApi
    BASE = "https://api.tumblr.com".freeze

    DEFAULT_TRANSPORT = lambda do |req, base|
      Net::HTTP.start(base.host, base.port, use_ssl: base.scheme == "https") do |http|
        http.request(req)
      end
    end

    def initialize(access_token:, blog_identifier:, base_url: BASE, transport: DEFAULT_TRANSPORT)
      @base = URI(base_url)
      @token = access_token
      @blog = blog_identifier
      @transport = transport
    end

    def create_post(text, image_paths: [])
      content = []
      content << { "type" => "text", "text" => text } unless text.to_s.empty?
      image_paths.each_with_index do |p, i|
        content << { "type" => "image",
                     "media" => [{ "type" => mime_for(p), "identifier" => "image-#{i}" }] }
      end
      body_json = JSON.generate({ "content" => content })
      path = "/v2/blog/#{@blog}/posts"

      req =
        if image_paths.empty?
          r = Net::HTTP::Post.new(path)
          r["Content-Type"] = "application/json"
          r.body = body_json
          r
        else
          build_multipart(path, body_json, image_paths)
        end
      request(req)
    end

    private

    def build_multipart(path, body_json, image_paths)
      boundary = "----SnsMultipost#{SecureRandom.hex(8)}"
      body = "".b
      body << "--#{boundary}\r\n"
      body << "Content-Disposition: form-data; name=\"json\"\r\n"
      body << "Content-Type: application/json\r\n\r\n"
      body << body_json.b << "\r\n"
      image_paths.each_with_index do |p, i|
        body << "--#{boundary}\r\n"
        body << "Content-Disposition: form-data; name=\"image-#{i}\"; filename=\"#{File.basename(p)}\"\r\n"
        body << "Content-Type: #{mime_for(p)}\r\n\r\n"
        body << File.binread(p) << "\r\n"
      end
      body << "--#{boundary}--\r\n"
      req = Net::HTTP::Post.new(path)
      req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      req.body = body
      req
    end

    def mime_for(path)
      case File.extname(path).downcase
      when ".png"  then "image/png"
      when ".gif"  then "image/gif"
      when ".webp" then "image/webp"
      else "image/jpeg"
      end
    end

    def request(req)
      req["Authorization"] = "Bearer #{@token}"
      res = @transport.call(req, @base)
      code = res.code.to_i
      unless code.between?(200, 299)
        raise "Tumblr API error #{res.code}: #{res.body.to_s[0, 200]}"
      end
      JSON.parse(res.body)
    end
  end
end
