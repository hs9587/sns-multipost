# test/bluesky_api_test.rb
require_relative "test_helper"
require "bluesky_api"
require "json"

class BlueskyApiTest < Minitest::Test
  # 記録付きの偽トランスポート。呼ばれたリクエストを貯め、順に応答を返す
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

  def test_login_posts_credentials_and_stores_jwt
    t, calls = fake([[200, JSON.generate("accessJwt" => "JWT1", "did" => "did:plc:abc")]])
    api = SnsMultipost::BlueskyApi.new(handle: "me.bsky.social", app_password: "pw", transport: t)
    res = api.login
    assert_equal "did:plc:abc", res["did"]
    c = calls.first
    assert_equal "POST", c[:method]
    assert_equal "/xrpc/com.atproto.server.createSession", c[:path]
    body = JSON.parse(c[:body])
    assert_equal "me.bsky.social", body["identifier"]
    assert_equal "pw", body["password"]
    assert_nil c[:auth] # createSession は無認証
  end

  def test_upload_blob_sends_bytes_with_auth_and_returns_blob
    Dir.mktmpdir do |dir|
      png = File.join(dir, "a.png")
      File.binwrite(png, "PNGBYTES")
      t, calls = fake([
        [200, JSON.generate("accessJwt" => "JWT1", "did" => "did:plc:abc")],
        [200, JSON.generate("blob" => { "$type" => "blob", "ref" => { "$link" => "bafyxxx" } })]
      ])
      api = SnsMultipost::BlueskyApi.new(handle: "me", app_password: "pw", transport: t)
      blob = api.upload_blob(png)
      assert_equal "bafyxxx", blob["ref"]["$link"]
      up = calls.last
      assert_equal "/xrpc/com.atproto.repo.uploadBlob", up[:path]
      assert_equal "image/png", up[:ctype]
      assert_equal "Bearer JWT1", up[:auth]
      assert_equal "PNGBYTES", up[:body]
    end
  end

  def test_create_post_builds_record_with_image_embed
    t, calls = fake([
      [200, JSON.generate("accessJwt" => "JWT1", "did" => "did:plc:abc")],
      [200, JSON.generate("uri" => "at://did:plc:abc/app.bsky.feed.post/rkey1", "cid" => "cidx")]
    ])
    api = SnsMultipost::BlueskyApi.new(handle: "me", app_password: "pw", transport: t)
    blob = { "$type" => "blob", "ref" => { "$link" => "bafyxxx" } }
    res = api.create_post("こんにちは", blobs: [blob], created_at: "2026-07-20T00:00:00Z")
    assert_equal "at://did:plc:abc/app.bsky.feed.post/rkey1", res["uri"]
    rec = JSON.parse(calls.last[:body])
    assert_equal "did:plc:abc", rec["repo"]
    assert_equal "app.bsky.feed.post", rec["collection"]
    assert_equal "こんにちは", rec["record"]["text"]
    assert_equal "2026-07-20T00:00:00Z", rec["record"]["createdAt"]
    assert_equal "app.bsky.embed.images", rec["record"]["embed"]["$type"]
    assert_equal "bafyxxx", rec["record"]["embed"]["images"][0]["image"]["ref"]["$link"]
  end

  def test_create_post_without_images_has_no_embed
    t, calls = fake([
      [200, JSON.generate("accessJwt" => "JWT1", "did" => "did:plc:abc")],
      [200, JSON.generate("uri" => "at://x/app.bsky.feed.post/r", "cid" => "c")]
    ])
    api = SnsMultipost::BlueskyApi.new(handle: "me", app_password: "pw", transport: t)
    api.create_post("text only", blobs: [], created_at: "2026-07-20T00:00:00Z")
    rec = JSON.parse(calls.last[:body])
    refute rec["record"].key?("embed")
  end

  def test_non_2xx_raises
    t, _ = fake([[401, '{"error":"AuthRequired"}']])
    api = SnsMultipost::BlueskyApi.new(handle: "me", app_password: "pw", transport: t)
    err = assert_raises(RuntimeError) { api.login }
    assert_match(/Bluesky API error 401/, err.message)
  end
end
