# test/x_api_test.rb
require_relative "test_helper"
require "x_api"
require "json"

class XApiTest < Minitest::Test
  class FakeResp
    attr_reader :code, :body
    def initialize(code, body) = (@code, @body = code.to_s, body)
  end

  def fake(responses)
    calls = []
    t = lambda do |req, base|
      calls << { method: req.method, host: base.host, path: req.path,
                 ctype: req["Content-Type"], auth: req["Authorization"], body: req.body }
      FakeResp.new(*responses.shift)
    end
    [t, calls]
  end

  def api(transport)
    SnsMultipost::XApi.new(
      consumer_key: "ck", consumer_secret: "cs",
      access_token: "at", access_token_secret: "ats",
      transport: transport, nonce_gen: -> { "NONCE" }, clock: -> { 100 })
  end

  def test_create_tweet_text_only_sends_json_with_oauth1
    t, calls = fake([[201, JSON.generate("data" => { "id" => "555", "text" => "やあ" })]])
    res = api(t).create_tweet("やあ")
    assert_equal "555", res["data"]["id"]
    c = calls.first
    assert_equal "POST", c[:method]
    assert_equal "api.twitter.com", c[:host]
    assert_equal "/2/tweets", c[:path]
    assert_match(%r{application/json}, c[:ctype])
    assert c[:auth].start_with?("OAuth ")
    body = JSON.parse(c[:body])
    assert_equal "やあ", body["text"]
    refute body.key?("media")
  end

  def test_create_tweet_with_media_ids_adds_media_block
    t, calls = fake([[201, JSON.generate("data" => { "id" => "9" })]])
    api(t).create_tweet("写真", media_ids: %w[m1 m2])
    body = JSON.parse(calls.first[:body])
    assert_equal({ "media_ids" => %w[m1 m2] }, body["media"])
  end

  def test_upload_media_sends_multipart_and_returns_id
    Dir.mktmpdir do |dir|
      png = File.join(dir, "a.png"); File.binwrite(png, "PNGBYTES")
      t, calls = fake([[200, JSON.generate("data" => { "id" => "media-123" })]])
      id = api(t).upload_media(png)
      assert_equal "media-123", id
      c = calls.first
      assert_equal "POST", c[:method]
      assert_equal "/2/media/upload", c[:path]
      assert_match(%r{multipart/form-data; boundary=}, c[:ctype])
      assert c[:auth].start_with?("OAuth ")
      assert_includes c[:body], "name=\"media\""
      assert_includes c[:body], "PNGBYTES"
    end
  end

  def test_non_2xx_raises
    t, _ = fake([[403, '{"title":"Forbidden"}']])
    err = assert_raises(RuntimeError) { api(t).create_tweet("x") }
    assert_match(/X API error 403/, err.message)
  end
end
