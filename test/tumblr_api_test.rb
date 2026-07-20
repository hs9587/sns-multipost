# test/tumblr_api_test.rb
require_relative "test_helper"
require "tumblr_api"
require "json"

class TumblrApiTest < Minitest::Test
  class FakeResp
    attr_reader :code, :body
    def initialize(code, body) = (@code, @body = code.to_s, body)
  end

  def fake(responses)
    calls = []
    t = lambda do |req, base|
      calls << { method: req.method, path: req.path, ctype: req["Content-Type"],
                 auth: req["Authorization"], body: req.body, host: base.host }
      FakeResp.new(*responses.shift)
    end
    [t, calls]
  end

  def api(transport)
    SnsMultipost::TumblrApi.new(access_token: "TOK", blog_identifier: "hs9587.tumblr.com",
                                transport: transport)
  end

  def test_text_only_post_sends_json_with_bearer
    t, calls = fake([[201, JSON.generate("response" => { "id" => 123, "id_string" => "123" })]])
    res = api(t).create_post("こんにちは")
    assert_equal "123", res["response"]["id_string"]
    c = calls.first
    assert_equal "POST", c[:method]
    assert_equal "/v2/blog/hs9587.tumblr.com/posts", c[:path]
    assert_equal "api.tumblr.com", c[:host]
    assert_equal "Bearer TOK", c[:auth]
    assert_match(%r{application/json}, c[:ctype])
    body = JSON.parse(c[:body])
    assert_equal [{ "type" => "text", "text" => "こんにちは" }], body["content"]
  end

  def test_post_with_images_uses_multipart_and_identifiers
    Dir.mktmpdir do |dir|
      a = File.join(dir, "a.jpg"); File.binwrite(a, "AAA")
      b = File.join(dir, "b.png"); File.binwrite(b, "BBB")
      t, calls = fake([[201, JSON.generate("response" => { "id" => 9, "id_string" => "9" })]])
      api(t).create_post("写真だよ", image_paths: [a, b])
      c = calls.first
      assert_match(%r{multipart/form-data; boundary=}, c[:ctype])
      # json パートに content（text + image ブロック）が入る
      assert_includes c[:body], "name=\"json\""
      assert_includes c[:body], "\"identifier\":\"image-0\""
      assert_includes c[:body], "\"identifier\":\"image-1\""
      # 画像パートがフィールド名 image-0 / image-1 で入る
      assert_includes c[:body], "name=\"image-0\"; filename=\"a.jpg\""
      assert_includes c[:body], "name=\"image-1\"; filename=\"b.png\""
      assert_includes c[:body], "AAA"
      assert_includes c[:body], "BBB"
      # image ブロックの MIME
      assert_includes c[:body], "\"type\":\"image/jpeg\""
      assert_includes c[:body], "\"type\":\"image/png\""
    end
  end

  def test_non_2xx_raises
    t, _ = fake([[401, '{"meta":{"status":401,"msg":"Unauthorized"}}']])
    err = assert_raises(RuntimeError) { api(t).create_post("x") }
    assert_match(/Tumblr API error 401/, err.message)
  end
end
