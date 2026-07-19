require_relative "test_helper"
require "fedibird_api"

class FedibirdApiTest < Minitest::Test
  FakeRes = Struct.new(:code, :body)

  def api_with(transport)
    SnsMultipost::FedibirdApi.new(
      base_url: "https://fedibird.com", access_token: "tok", transport: transport)
  end

  def test_statuses_builds_request_and_parses
    captured = nil
    api = api_with(->(req, _base) { captured = req; FakeRes.new("200", '[{"id":"1"}]') })
    res = api.statuses(account_id: "42", since_id: "9")
    assert_equal [{ "id" => "1" }], res
    assert_match %r{\A/api/v1/accounts/42/statuses\?}, captured.path
    assert_includes captured.path, "since_id=9"
    assert_includes captured.path, "exclude_reblogs=true"
    assert_equal "Bearer tok", captured["Authorization"]
  end

  def test_post_status_sends_json
    captured = nil
    api = api_with(->(req, _base) {
      captured = req
      FakeRes.new("200", '{"id":"10","url":"https://fedibird.com/@hs9587/10"}')
    })
    st = api.post_status("こんにちは", media_ids: ["5"])
    assert_equal "10", st["id"]
    body = JSON.parse(captured.body)
    assert_equal "こんにちは", body["status"]
    assert_equal ["5"], body["media_ids"]
    assert_equal "application/json", captured["Content-Type"]
  end

  def test_upload_media_multipart
    Dir.mktmpdir do |dir|
      file = File.join(dir, "a.png")
      File.binwrite(file, "PNGDATA")
      captured = nil
      api = api_with(->(req, _base) { captured = req; FakeRes.new("200", '{"id":"m1"}') })
      res = api.upload_media(file)
      assert_equal "m1", res["id"]
      assert_match %r{\Amultipart/form-data; boundary=}, captured["Content-Type"]
      assert_includes captured.body, "PNGDATA"
      assert_includes captured.body, 'filename="a.png"'
    end
  end

  def test_non_2xx_raises
    api = api_with(->(_req, _base) { FakeRes.new("401", "unauthorized") })
    err = assert_raises(RuntimeError) { api.verify_credentials }
    assert_match(/401/, err.message)
  end
end
