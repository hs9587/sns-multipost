require_relative "test_helper"
require "oauth_refresh"
require "json"
require "uri"

class OAuthRefreshTest < Minitest::Test
  class FakeResp
    attr_reader :code, :body
    def initialize(code, body) = (@code, @body = code.to_s, body)
  end

  def test_posts_refresh_grant_and_returns_access_token
    calls = []
    t = lambda do |req, base|
      calls << { method: req.method, host: base.host, path: req.path,
                 ctype: req["Content-Type"], body: req.body }
      FakeResp.new(200, JSON.generate("access_token" => "AT-123", "expires_in" => 3599))
    end
    tok = SnsMultipost::OAuthRefresh.access_token(
      token_uri: "https://oauth2.googleapis.com/token",
      client_id: "CID", client_secret: "CSEC", refresh_token: "RT", transport: t)
    assert_equal "AT-123", tok
    c = calls.first
    assert_equal "POST", c[:method]
    assert_equal "oauth2.googleapis.com", c[:host]
    assert_equal "/token", c[:path]
    assert_match(%r{application/x-www-form-urlencoded}, c[:ctype])
    params = URI.decode_www_form(c[:body]).to_h
    assert_equal "refresh_token", params["grant_type"]
    assert_equal "CID", params["client_id"]
    assert_equal "CSEC", params["client_secret"]
    assert_equal "RT", params["refresh_token"]
  end

  def test_non_2xx_raises
    t = ->(_req, _base) { FakeResp.new(400, '{"error":"invalid_grant"}') }
    err = assert_raises(RuntimeError) do
      SnsMultipost::OAuthRefresh.access_token(
        token_uri: "https://oauth2.googleapis.com/token",
        client_id: "x", client_secret: "y", refresh_token: "z", transport: t)
    end
    assert_match(/OAuth refresh error 400/, err.message)
  end

  def test_missing_access_token_raises
    t = ->(_req, _base) { FakeResp.new(200, '{"expires_in":3599}') }
    err = assert_raises(RuntimeError) do
      SnsMultipost::OAuthRefresh.access_token(
        token_uri: "https://oauth2.googleapis.com/token",
        client_id: "x", client_secret: "y", refresh_token: "z", transport: t)
    end
    assert_match(/no access_token/, err.message)
  end
end
