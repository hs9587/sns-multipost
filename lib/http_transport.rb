require "net/http"
require "socket"
require "timeout"
require_relative "delivery_error"

module SnsMultipost
  class HttpTransport
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30
    WRITE_TIMEOUT = 30
    ATTEMPTS = 3
    IDEMPOTENT_METHODS = %w[GET HEAD PUT DELETE OPTIONS TRACE].freeze
    RETRYABLE_CODES = [408, 425, 429, 500, 502, 503, 504].freeze
    DELIVERY_MARKER = :@sns_multipost_delivery_request

    def self.call(request, base)
      @default ||= new
      @default.call(request, base)
    end

    def self.mark_delivery(request)
      request.instance_variable_set(DELIVERY_MARKER, true)
      request
    end

    def self.delivery_request?(request)
      request.instance_variable_get(DELIVERY_MARKER) == true
    end

    def initialize(open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT,
                   write_timeout: WRITE_TIMEOUT, attempts: ATTEMPTS,
                   sleeper: ->(seconds) { sleep seconds },
                   logger: ->(message) { warn message }, performer: nil)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @write_timeout = write_timeout
      @attempts = attempts
      @sleeper = sleeper
      @logger = logger
      @performer = performer || method(:perform)
    end

    def call(request, base)
      idempotent = IDEMPOTENT_METHODS.include?(request.method.to_s.upcase)
      delivery = self.class.delivery_request?(request)
      @attempts.times do |attempt|
        begin
          response = @performer.call(request, base)
          if idempotent && RETRYABLE_CODES.include?(response.code.to_i) && retry_left?(attempt)
            pause(request, base, attempt, "HTTP #{response.code}")
            next
          end
          if delivery && delivery_unknown_response?(response)
            raise DeliveryUnknownError,
                  "#{request.method} #{base.host} returned HTTP #{response.code}; delivery result is unknown"
          end
          return response
        rescue StandardError => e
          if delivery && delivery_unknown_exception?(e)
            raise DeliveryUnknownError.wrap(e, context: "#{request.method} #{base.host}")
          end
          raise unless retry_left?(attempt) && retryable_exception?(e, idempotent)

          pause(request, base, attempt, "#{e.class}: #{e.message}")
        end
      end
      raise "HTTP request retry loop ended unexpectedly"
    end

    private

    def perform(request, base)
      Net::HTTP.start(
        base.host, base.port,
        use_ssl: base.scheme == "https",
        open_timeout: @open_timeout,
        read_timeout: @read_timeout,
        write_timeout: @write_timeout
      ) { |http| http.request(request) }
    end

    def retry_left?(attempt)
      attempt + 1 < @attempts
    end

    def retryable_exception?(error, idempotent)
      preconnect_error?(error) || (idempotent && transient_error?(error))
    end

    def preconnect_error?(error)
      error.is_a?(SocketError) || error.is_a?(Net::OpenTimeout) ||
        system_error?(error, :ECONNREFUSED, :EHOSTUNREACH, :ENETUNREACH)
    end

    def transient_error?(error)
      error.is_a?(Net::ReadTimeout) ||
        (defined?(Net::WriteTimeout) && error.is_a?(Net::WriteTimeout)) ||
        error.is_a?(EOFError) ||
        system_error?(error, :ECONNRESET, :ETIMEDOUT, :EPIPE)
    end

    def delivery_unknown_exception?(error)
      !error.is_a?(DeliveryUnknownError) && transient_error?(error)
    end

    def delivery_unknown_response?(response)
      [408, 500, 502, 503, 504].include?(response.code.to_i)
    end

    def system_error?(error, *names)
      names.any? do |name|
        Errno.const_defined?(name) && error.is_a?(Errno.const_get(name))
      end
    end

    def pause(request, base, attempt, reason)
      delay = 2**attempt
      @logger.call(
        "HTTP retry #{attempt + 1}/#{@attempts - 1} " \
        "#{request.method} #{base.host}: #{reason} (#{delay}秒後)")
      @sleeper.call(delay)
    end
  end
end
