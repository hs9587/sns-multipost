require_relative "test_helper"
require "token_store"

class TokenStoreTest < Minitest::Test
  def test_load_missing_returns_empty_hash
    Dir.mktmpdir do |dir|
      store = SnsMultipost::TokenStore.new(File.join(dir, "nope.json"))
      assert_equal({}, store.load)
    end
  end

  def test_save_then_load_roundtrip
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sub", "tok.json") # 親ディレクトリはまだ無い
      store = SnsMultipost::TokenStore.new(path)
      store.save("access_token" => "AT", "refresh_token" => "RT", "expires_at" => 100)
      assert File.exist?(path)
      assert_equal({ "access_token" => "AT", "refresh_token" => "RT", "expires_at" => 100 },
                   store.load)
    end
  end

  def test_save_overwrites_atomically_without_leaving_tmp
    Dir.mktmpdir do |dir|
      path = File.join(dir, "tok.json")
      store = SnsMultipost::TokenStore.new(path)
      store.save("v" => 1)
      store.save("v" => 2)
      assert_equal({ "v" => 2 }, store.load)
      # 一時ファイルが残っていない（json はちょうど1つ）
      assert_equal [path], Dir[File.join(dir, "*")].select { |p| File.file?(p) }
    end
  end
end
