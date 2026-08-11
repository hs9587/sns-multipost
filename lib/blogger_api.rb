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

    def insert_post(title:, html:, is_draft: false)
      path = "/blogger/v3/blogs/#{@blog_id}/posts"
      path += "?isDraft=true" if is_draft
      req = Net::HTTP::Post.new(path)
      req["Content-Type"] = "application/json"
      req.body = JSON.generate({ "kind" => "blogger#post", "title" => title, "content" => html })
      request(req)
    end

    def delete_post(post_id)
      req = Net::HTTP::Delete.new("/blogger/v3/blogs/#{@blog_id}/posts/#{post_id}")
      request(req, allow_not_found: true)
      true
    end

    private

    def request(req, allow_not_found: false)
      req["Authorization"] = "Bearer #{@token}"
      res = @transport.call(req, @base)
      code = res.code.to_i
      return {} if allow_not_found && code == 404
      unless code.between?(200, 299)
        raise "Blogger API error #{res.code}: #{res.body.to_s[0, 200]}"
      end
      body = res.body.to_s
      body.empty? ? {} : JSON.parse(body)
    end
  end
end
