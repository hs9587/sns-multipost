require_relative "test_helper"
require "blogger_api"
require "json"

class BloggerApiTest < Minitest::Test
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

  def test_insert_post_sends_json_with_bearer_and_returns_id_url
    t, calls = fake([[200, JSON.generate(
      "kind" => "blogger#post", "id" => "777",
      "url" => "https://hs9587.blogspot.com/2026/07/x.html", "title" => "タイトル")]])
    api = SnsMultipost::BloggerApi.new(blog_id: "42", access_token: "AT", transport: t)
    res = api.insert_post(title: "タイトル", html: "<p>本文</p>")
    assert_equal "777", res["id"]
    assert_equal "https://hs9587.blogspot.com/2026/07/x.html", res["url"]
    c = calls.first
    assert_equal "POST", c[:method]
    assert_equal "www.googleapis.com", c[:host]
    assert_equal "/blogger/v3/blogs/42/posts", c[:path]
    assert_equal "Bearer AT", c[:auth]
    assert_match(%r{application/json}, c[:ctype])
    body = JSON.parse(c[:body])
    assert_equal "blogger#post", body["kind"]
    assert_equal "タイトル", body["title"]
    assert_equal "<p>本文</p>", body["content"]
  end

  def test_non_2xx_raises
    t, _ = fake([[403, '{"error":{"message":"forbidden"}}']])
    api = SnsMultipost::BloggerApi.new(blog_id: "42", access_token: "AT", transport: t)
    err = assert_raises(RuntimeError) { api.insert_post(title: "t", html: "<p>x</p>") }
    assert_match(/Blogger API error 403/, err.message)
  end
end
