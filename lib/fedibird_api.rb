require "net/http"
require "json"
require "uri"
require "securerandom"

module SnsMultipost
  class FedibirdApi
    DEFAULT_TRANSPORT = lambda do |req, base|
      Net::HTTP.start(base.host, base.port, use_ssl: base.scheme == "https") do |http|
        http.request(req)
      end
    end

    def initialize(base_url:, access_token:, transport: DEFAULT_TRANSPORT)
      @base = URI(base_url)
      @token = access_token
      @transport = transport
    end

    def verify_credentials
      get("/api/v1/accounts/verify_credentials")
    end

    def statuses(account_id:, since_id: nil, max_id: nil, limit: 40)
      q = { "limit" => limit, "exclude_reblogs" => true }
      q["since_id"] = since_id if since_id
      q["max_id"] = max_id if max_id
      get("/api/v1/accounts/#{account_id}/statuses", q)
    end

    def post_status(text, media_ids: [])
      req = Net::HTTP::Post.new("/api/v1/statuses")
      req["Content-Type"] = "application/json"
      req.body = JSON.generate({ status: text, media_ids: media_ids })
      request(req)
    end

    def upload_media(path)
      boundary = "----SnsMultipost#{SecureRandom.hex(8)}"
      body = +""
      body << "--#{boundary}\r\n"
      body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{File.basename(path)}\"\r\n"
      body << "Content-Type: application/octet-stream\r\n\r\n"
      body << File.binread(path)
      body << "\r\n--#{boundary}--\r\n"
      req = Net::HTTP::Post.new("/api/v2/media")
      req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      req.body = body
      request(req)
    end

    private

    def get(path, query = nil)
      full = query ? "#{path}?#{URI.encode_www_form(query)}" : path
      request(Net::HTTP::Get.new(full))
    end

    def request(req)
      req["Authorization"] = "Bearer #{@token}"
      res = @transport.call(req, @base)
      code = res.code.to_i
      unless code.between?(200, 299)
        raise "Fedibird API error #{res.code}: #{res.body.to_s[0, 200]}"
      end
      JSON.parse(res.body)
    end
  end
end
