require "net/http"
require "json"
require "uri"

module SnsMultipost
  class BloggerApi
    BASE = "https://www.googleapis.com".freeze

    DEFAULT_TRANSPORT = lambda do |req, base|
      Net::HTTP.start(base.host, base.port, use_ssl: base.scheme == "https") do |http|
        http.request(req)
      end
    end

    def initialize(blog_id:, access_token:, base_url: BASE, transport: DEFAULT_TRANSPORT)
      @base = URI(base_url)
      @blog_id = blog_id
      @token = access_token
      @transport = transport
    end

    def insert_post(title:, html:)
      req = Net::HTTP::Post.new("/blogger/v3/blogs/#{@blog_id}/posts")
      req["Content-Type"] = "application/json"
      req.body = JSON.generate({ "kind" => "blogger#post", "title" => title, "content" => html })
      request(req)
    end

    private

    def request(req)
      req["Authorization"] = "Bearer #{@token}"
      res = @transport.call(req, @base)
      code = res.code.to_i
      unless code.between?(200, 299)
        raise "Blogger API error #{res.code}: #{res.body.to_s[0, 200]}"
      end
      JSON.parse(res.body)
    end
  end
end
