require_relative "test_helper"
require "threads_token"

class ThreadsTokenTest < Minitest::Test
  class MemStore
    attr_reader :data
    def initialize(data = {}) = (@data = data)
    def load = @data
    def save(data) = (@data = data)
  end

  class FakeRefresher
    attr_reader :tokens
    def initialize(response) = (@response = response; @tokens = [])
    def refresh(access_token:)
      @tokens << access_token
      @response
    end
  end

  def test_reuses_stored_token_before_refresh_window
    store = MemStore.new("access_token" => "STORED", "expires_at" => 2_000_000)
    refresher = FakeRefresher.new("access_token" => "NEW")
    token = SnsMultipost::ThreadsToken.new({}, store: store, refresher: refresher,
                                           clock: -> { 1_000_000 })

    assert_equal "STORED", token.access_token
    assert_empty refresher.tokens
  end

  def test_refreshes_stored_token_during_last_seven_days
    store = MemStore.new(
      "access_token" => "OLD", "expires_at" => 1_000_000 + 6 * 24 * 60 * 60,
      "user_id" => "42")
    refresher = FakeRefresher.new("access_token" => "NEW", "expires_in" => 5_184_000)
    token = SnsMultipost::ThreadsToken.new({}, store: store, refresher: refresher,
                                           clock: -> { 1_000_000 })

    assert_equal "NEW", token.access_token
    assert_equal ["OLD"], refresher.tokens
    assert_equal "42", store.data["user_id"]
    assert_equal 1_000_000 + 5_184_000, store.data["expires_at"]
  end

  def test_uses_configured_token_when_store_is_empty
    token = SnsMultipost::ThreadsToken.new(
      { "access_token" => "CONFIG" }, store: MemStore.new,
      refresher: FakeRefresher.new({}), clock: -> { 1_000_000 })

    assert_equal "CONFIG", token.access_token
  end

  def test_missing_token_raises_with_auth_command
    token = SnsMultipost::ThreadsToken.new(
      {}, store: MemStore.new, refresher: FakeRefresher.new({}), clock: -> { 1_000_000 })

    error = assert_raises(RuntimeError) { token.access_token }
    assert_match(/threads_auth --authorize/, error.message)
  end
end
