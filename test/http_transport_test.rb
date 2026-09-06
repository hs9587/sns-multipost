require_relative "test_helper"
require "http_transport"
require "uri"

class HttpTransportTest < Minitest::Test
  Response = Struct.new(:code)

  def test_retries_idempotent_request_after_read_timeout
    calls = 0
    sleeps = []
    transport = build_transport(sleeps) do
      calls += 1
      raise Net::ReadTimeout if calls < 3

      Response.new("200")
    end

    response = transport.call(Net::HTTP::Get.new("/items"), URI("https://example.test"))

    assert_equal "200", response.code
    assert_equal 3, calls
    assert_equal [1, 2], sleeps
  end

  def test_retries_post_only_when_connection_was_not_started
    calls = 0
    transport = build_transport([]) do
      calls += 1
      raise SocketError, "name not known" if calls == 1

      Response.new("201")
    end

    response = transport.call(Net::HTTP::Post.new("/posts"), URI("https://example.test"))

    assert_equal "201", response.code
    assert_equal 2, calls
  end

  def test_does_not_retry_post_after_ambiguous_read_timeout
    calls = 0
    transport = build_transport([]) do
      calls += 1
      raise Net::ReadTimeout
    end

    assert_raises(Net::ReadTimeout) do
      transport.call(Net::HTTP::Post.new("/posts"), URI("https://example.test"))
    end
    assert_equal 1, calls
  end

  def test_retries_retryable_response_only_for_idempotent_request
    get_calls = 0
    get_transport = build_transport([]) do
      get_calls += 1
      Response.new(get_calls == 1 ? "503" : "200")
    end
    post_calls = 0
    post_transport = build_transport([]) do
      post_calls += 1
      Response.new("503")
    end

    assert_equal "200", get_transport.call(
      Net::HTTP::Get.new("/items"), URI("https://example.test")).code
    assert_equal "503", post_transport.call(
      Net::HTTP::Post.new("/posts"), URI("https://example.test")).code
    assert_equal 2, get_calls
    assert_equal 1, post_calls
  end

  private

  def build_transport(sleeps, &performer)
    SnsMultipost::HttpTransport.new(
      sleeper: ->(seconds) { sleeps << seconds },
      logger: ->(_message) {}, performer: performer)
  end
end
