require_relative "test_helper"
require "threads_api"
require "json"
require "uri"

class ThreadsApiTest < Minitest::Test
  class FakeResp
    attr_reader :code, :body
    def initialize(code, body) = (@code, @body = code.to_s, body)
  end

  def fake(response)
    calls = []
    transport = lambda do |req, base|
      calls << { method: req.method, path: req.path, auth: req["Authorization"],
                 ctype: req["Content-Type"], body: req.body, host: base.host }
      FakeResp.new(*response)
    end
    [transport, calls]
  end

  def test_create_text_post_auto_publishes_with_bearer_token
    transport, calls = fake([200, JSON.generate("id" => "123")])
    api = SnsMultipost::ThreadsApi.new(access_token: "TOK", transport: transport)

    assert_equal "123", api.create_text_post("こんにちは")["id"]
    call = calls.first
    assert_equal "POST", call[:method]
    assert_equal "/me/threads", call[:path]
    assert_equal "graph.threads.net", call[:host]
    assert_equal "Bearer TOK", call[:auth]
    params = URI.decode_www_form(call[:body]).to_h
    assert_equal "TEXT", params["media_type"]
    assert_equal "こんにちは", params["text"]
    assert_equal "true", params["auto_publish_text"]
  end

  def test_non_2xx_raises
    transport, = fake([400, '{"error":{"message":"bad request"}}'])
    api = SnsMultipost::ThreadsApi.new(access_token: "TOK", transport: transport)

    error = assert_raises(RuntimeError) { api.create_text_post("x") }
    assert_match(/Threads API error 400/, error.message)
  end
end
