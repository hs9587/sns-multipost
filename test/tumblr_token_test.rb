# test/tumblr_token_test.rb
require_relative "test_helper"
require "tumblr_token"

class TumblrTokenTest < Minitest::Test
  # メモリ上の store（TokenStore 互換）
  class MemStore
    attr_reader :data
    def initialize(data = {}) = (@data = data)
    def load = @data
    def save(h) = (@data = h)
  end

  # 呼び出しを記録する refresher。渡された refresh_token を記録し、固定応答を返す
  class FakeRefresher
    attr_reader :calls
    def initialize(response) = (@calls = []; @response = response)
    def refresh(token_uri:, client_id:, client_secret:, refresh_token:)
      @calls << { token_uri: token_uri, refresh_token: refresh_token }
      @response
    end
  end

  CFG = { "client_id" => "CID", "client_secret" => "CSEC",
          "refresh_token" => "RT-config", "blog_identifier" => "hs9587.tumblr.com" }.freeze

  def test_first_run_seeds_refresh_token_from_config_and_persists_rotation
    store = MemStore.new({})
    refr = FakeRefresher.new(
      "access_token" => "AT1", "refresh_token" => "RT1", "expires_in" => 3600)
    tok = SnsMultipost::TumblrToken.new(CFG, store: store, refresher: refr, clock: -> { 1000 })
    assert_equal "AT1", tok.access_token
    # config の refresh_token を種に refresh した
    assert_equal "RT-config", refr.calls.first[:refresh_token]
    assert_equal "https://api.tumblr.com/v2/oauth2/token", refr.calls.first[:token_uri]
    # 新トークン一式が保存された（ローテーション後の RT1 を保持）
    assert_equal "AT1", store.data["access_token"]
    assert_equal "RT1", store.data["refresh_token"]
    assert_equal 1000 + 3600, store.data["expires_at"]
  end

  def test_reuses_stored_token_when_not_expired
    store = MemStore.new(
      "access_token" => "AT-stored", "refresh_token" => "RT-stored", "expires_at" => 5000)
    refr = FakeRefresher.new("access_token" => "AT-new", "refresh_token" => "RT-new",
                             "expires_in" => 3600)
    tok = SnsMultipost::TumblrToken.new(CFG, store: store, refresher: refr, clock: -> { 4000 })
    assert_equal "AT-stored", tok.access_token
    assert_empty refr.calls # refresh していない
  end

  def test_refreshes_when_expired_and_uses_stored_refresh_token
    store = MemStore.new(
      "access_token" => "AT-old", "refresh_token" => "RT-stored", "expires_at" => 5000)
    refr = FakeRefresher.new("access_token" => "AT-new", "refresh_token" => "RT-new",
                             "expires_in" => 3600)
    tok = SnsMultipost::TumblrToken.new(CFG, store: store, refresher: refr, clock: -> { 4999 })
    # 4999 >= 5000 - 60 なので期限切れ扱い → refresh
    assert_equal "AT-new", tok.access_token
    assert_equal "RT-stored", refr.calls.first[:refresh_token] # config でなく store の RT
    assert_equal "RT-new", store.data["refresh_token"]
  end

  def test_keeps_refresh_token_when_response_omits_it
    store = MemStore.new({})
    refr = FakeRefresher.new("access_token" => "AT1", "expires_in" => 3600) # refresh_token 無し
    tok = SnsMultipost::TumblrToken.new(CFG, store: store, refresher: refr, clock: -> { 1000 })
    assert_equal "AT1", tok.access_token
    assert_equal "RT-config", store.data["refresh_token"] # 使った RT を維持
  end
end
