require "net/http"
require "json"
require "uri"

module SnsMultipost
  class ThreadsApi
    BASE = "https://graph.threads.net".freeze
    READY_STATUSES = %w[FINISHED PUBLISHED].freeze
    FAILED_STATUSES = %w[ERROR EXPIRED].freeze
    DEFAULT_STATUS_ATTEMPTS = 60

    DEFAULT_TRANSPORT = lambda do |req, base|
      Net::HTTP.start(base.host, base.port, use_ssl: base.scheme == "https") do |http|
        http.request(req)
      end
    end

    def initialize(access_token:, base_url: BASE, transport: DEFAULT_TRANSPORT,
                   sleeper: ->(seconds) { sleep seconds },
                   status_attempts: DEFAULT_STATUS_ATTEMPTS)
      @base = URI(base_url)
      @token = access_token
      @transport = transport
      @sleeper = sleeper
      @status_attempts = status_attempts
    end

    def create_text_post(text)
      create_container(
        "media_type" => "TEXT",
        "text" => text,
        "auto_publish_text" => "true")
    end

    def create_image_post(text:, image_url:)
      container = create_container(
        "media_type" => "IMAGE",
        "image_url" => image_url,
        "text" => text)
      publish_ready_container(container_id(container))
    end

    def create_carousel_post(text:, image_urls:)
      urls = Array(image_urls)
      raise "Threads carouselには画像が2枚以上必要です" if urls.length < 2
      raise "Threads carouselの画像は20枚までです" if urls.length > 20

      children = urls.map do |url|
        child = create_container(
          "media_type" => "IMAGE",
          "image_url" => url,
          "is_carousel_item" => "true")
        id = container_id(child)
        wait_until_ready(id)
        id
      end
      carousel = create_container(
        "media_type" => "CAROUSEL",
        "children" => children.join(","),
        "text" => text)
      publish_ready_container(container_id(carousel))
    end

    private

    def create_container(params)
      req = Net::HTTP::Post.new("/me/threads")
      req.set_form_data(params)
      request(req)
    end

    def publish_ready_container(id)
      wait_until_ready(id)
      req = Net::HTTP::Post.new("/me/threads_publish")
      req.set_form_data("creation_id" => id)
      request(req)
    end

    def container_id(response)
      id = response["id"].to_s
      raise "Threads API response にコンテナIDがありません" if id.empty?

      id
    end

    def wait_until_ready(id)
      @status_attempts.times do |attempt|
        req = Net::HTTP::Get.new("/#{URI.encode_www_form_component(id)}?fields=id,status,error_message")
        response = request(req)
        status = response["status"].to_s.upcase
        return response if READY_STATUSES.include?(status)
        if FAILED_STATUSES.include?(status)
          detail = response["error_message"].to_s
          detail = "status=#{status}" if detail.empty?
          raise "Threads media container #{id}: #{detail}"
        end
        @sleeper.call(1) if attempt + 1 < @status_attempts
      end
      raise "Threads media container #{id} の処理が完了しません"
    end

    def request(req)
      req["Authorization"] = "Bearer #{@token}"
      res = @transport.call(req, @base)
      code = res.code.to_i
      unless code.between?(200, 299)
        raise "Threads API error #{res.code}: #{res.body.to_s[0, 200]}"
      end
      JSON.parse(res.body)
    end
  end
end
