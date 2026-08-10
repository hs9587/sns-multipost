require_relative "test_helper"
require "threads_api"
require "json"
require "uri"

class ThreadsApiTest < Minitest::Test
  class FakeResp
    attr_reader :code, :body
    def initialize(code, body) = (@code, @body = code.to_s, body)
  end

  def fake(*responses)
    calls = []
    transport = lambda do |req, base|
      calls << { method: req.method, path: req.path, auth: req["Authorization"],
                 ctype: req["Content-Type"], body: req.body, host: base.host }
      FakeResp.new(*responses.shift)
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

  def test_create_single_image_waits_until_ready_and_publishes
    transport, calls = fake(
      [200, JSON.generate("id" => "container-1")],
      [200, JSON.generate("id" => "container-1", "status" => "IN_PROGRESS")],
      [200, JSON.generate("id" => "container-1", "status" => "FINISHED")],
      [200, JSON.generate("id" => "post-1")])
    sleeps = []
    api = SnsMultipost::ThreadsApi.new(
      access_token: "TOK", transport: transport,
      sleeper: ->(seconds) { sleeps << seconds })

    assert_equal "post-1", api.create_image_post(
      text: "写真", image_url: "https://media.example/one.jpg")["id"]
    create_params = URI.decode_www_form(calls[0][:body]).to_h
    assert_equal "IMAGE", create_params["media_type"]
    assert_equal "https://media.example/one.jpg", create_params["image_url"]
    assert_equal "写真", create_params["text"]
    assert_equal "GET", calls[1][:method]
    assert_match(%r{\A/container-1\?fields=}, calls[1][:path])
    publish_params = URI.decode_www_form(calls[3][:body]).to_h
    assert_equal "/me/threads_publish", calls[3][:path]
    assert_equal "container-1", publish_params["creation_id"]
    assert_equal [1], sleeps
  end

  def test_create_carousel_creates_ready_children_parent_and_publishes
    transport, calls = fake(
      [200, JSON.generate("id" => "child-1")],
      [200, JSON.generate("status" => "FINISHED")],
      [200, JSON.generate("id" => "child-2")],
      [200, JSON.generate("status" => "FINISHED")],
      [200, JSON.generate("id" => "carousel-1")],
      [200, JSON.generate("status" => "FINISHED")],
      [200, JSON.generate("id" => "post-2")])
    api = SnsMultipost::ThreadsApi.new(access_token: "TOK", transport: transport)

    result = api.create_carousel_post(
      text: "二枚", image_urls: %w[https://m.example/1.jpg https://m.example/2.jpg])

    assert_equal "post-2", result["id"]
    first = URI.decode_www_form(calls[0][:body]).to_h
    second = URI.decode_www_form(calls[2][:body]).to_h
    parent = URI.decode_www_form(calls[4][:body]).to_h
    assert_equal "true", first["is_carousel_item"]
    assert_equal "true", second["is_carousel_item"]
    assert_equal "CAROUSEL", parent["media_type"]
    assert_equal "child-1,child-2", parent["children"]
    assert_equal "二枚", parent["text"]
  end

  def test_failed_container_status_raises_with_api_message
    transport, = fake(
      [200, JSON.generate("id" => "bad")],
      [200, JSON.generate("status" => "ERROR", "error_message" => "cannot fetch image")])
    api = SnsMultipost::ThreadsApi.new(access_token: "TOK", transport: transport)

    error = assert_raises(RuntimeError) do
      api.create_image_post(text: "写真", image_url: "https://media.example/bad.jpg")
    end
    assert_match(/cannot fetch image/, error.message)
  end

  def test_container_status_timeout_raises
    transport, = fake(
      [200, JSON.generate("id" => "slow")],
      [200, JSON.generate("status" => "IN_PROGRESS")],
      [200, JSON.generate("status" => "IN_PROGRESS")])
    api = SnsMultipost::ThreadsApi.new(
      access_token: "TOK", transport: transport,
      status_attempts: 2, sleeper: ->(_seconds) {})

    error = assert_raises(RuntimeError) do
      api.create_image_post(text: "写真", image_url: "https://media.example/slow.jpg")
    end
    assert_match(/処理が完了しません/, error.message)
  end

  def test_non_2xx_raises
    transport, = fake([400, '{"error":{"message":"bad request"}}'])
    api = SnsMultipost::ThreadsApi.new(access_token: "TOK", transport: transport)

    error = assert_raises(RuntimeError) { api.create_text_post("x") }
    assert_match(/Threads API error 400/, error.message)
  end
end
