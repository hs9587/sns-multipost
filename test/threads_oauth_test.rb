require_relative "test_helper"
require "threads_oauth"
require "json"
require "uri"

class ThreadsOAuthTest < Minitest::Test
  class FakeResp
    attr_reader :code, :body
    def initialize(code, body) = (@code, @body = code.to_s, body)
  end

  def fake(response)
    calls = []
    transport = lambda do |req, base|
      calls << { method: req.method, path: req.path, body: req.body, host: base.host }
      FakeResp.new(*response)
    end
    [transport, calls]
  end

  def test_authorization_url_contains_required_scope_and_state
    url = SnsMultipost::ThreadsOAuth.authorization_url(
      client_id: "APP", redirect_uri: "https://localhost/callback", state: "STATE")
    uri = URI(url)
    params = URI.decode_www_form(uri.query).to_h

    assert_equal "threads.net", uri.host
    assert_equal "APP", params["client_id"]
    assert_equal "threads_basic,threads_content_publish", params["scope"]
    assert_equal "code", params["response_type"]
    assert_equal "STATE", params["state"]
  end

  def test_exchange_code_posts_authorization_code_grant
    transport, calls = fake([200, JSON.generate(
      "access_token" => "SHORT", "user_id" => "42")])
    result = SnsMultipost::ThreadsOAuth.exchange_code(
      client_id: "APP", client_secret: "SECRET",
      redirect_uri: "https://localhost/callback", code: "CODE", transport: transport)

    assert_equal "SHORT", result["access_token"]
    call = calls.first
    assert_equal "POST", call[:method]
    assert_equal "/oauth/access_token", call[:path]
    params = URI.decode_www_form(call[:body]).to_h
    assert_equal "authorization_code", params["grant_type"]
    assert_equal "CODE", params["code"]
    assert_equal "SECRET", params["client_secret"]
  end

  def test_exchange_and_refresh_long_lived_tokens
    exchange_transport, exchange_calls = fake([200, JSON.generate(
      "access_token" => "LONG", "expires_in" => 5_184_000)])
    refresh_transport, refresh_calls = fake([200, JSON.generate(
      "access_token" => "NEW", "expires_in" => 5_184_000)])

    long = SnsMultipost::ThreadsOAuth.exchange_long_lived(
      client_secret: "SECRET", access_token: "SHORT", transport: exchange_transport)
    refreshed = SnsMultipost::ThreadsOAuth.refresh(
      access_token: "LONG", transport: refresh_transport)

    assert_equal "LONG", long["access_token"]
    assert_equal "NEW", refreshed["access_token"]
    exchange_params = URI.decode_www_form(URI(exchange_calls.first[:path]).query).to_h
    refresh_params = URI.decode_www_form(URI(refresh_calls.first[:path]).query).to_h
    assert_equal "th_exchange_token", exchange_params["grant_type"]
    assert_equal "SECRET", exchange_params["client_secret"]
    assert_equal "SHORT", exchange_params["access_token"]
    assert_equal "th_refresh_token", refresh_params["grant_type"]
    assert_equal "LONG", refresh_params["access_token"]
  end

  def test_non_2xx_raises
    transport, = fake([401, '{"error":{"message":"invalid token"}}'])

    error = assert_raises(RuntimeError) do
      SnsMultipost::ThreadsOAuth.refresh(access_token: "bad", transport: transport)
    end
    assert_match(/Threads OAuth error 401/, error.message)
  end
end
