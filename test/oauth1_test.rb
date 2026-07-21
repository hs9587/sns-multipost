# test/oauth1_test.rb
require_relative "test_helper"
require "oauth1"

class OAuth1Test < Minitest::Test
  # X 公式 "Creating a signature" の worked example（docs で実値確認済み。
  # ブリーフの記憶値のうち consumer secret / token secret に一文字違いがあったため
  # 実値に修正。signature と url はブリーフの記憶値が実値と一致していた）
  KNOWN_CONSUMER_KEY    = "xvz1evFS4wEEPTGEFPHBog"
  KNOWN_CONSUMER_SECRET = "kAcSOqF21Fu85e7zjz7ZN2U4ZRhfV3WpwPAoE3Z7kBw"
  KNOWN_TOKEN           = "370773112-GmHxMAgYyLbNEtIKZeRNFsMKPR9EyMZeS9weJAEb"
  KNOWN_TOKEN_SECRET    = "LswwdoUaIvS8ltyTt5jkRh4J50vUPVVHtR2YPi5kE"
  KNOWN_NONCE           = "kYjzVBB8Y0ZFabxSWbWovY3uYSQ2pTgmZeNu2VS4cg"
  KNOWN_TIMESTAMP       = "1318622958"
  KNOWN_SIGNATURE       = "hCtSmYh+iHYCEqBWrE7C7hYmtUk=" # 期待値（docs で確認）

  def test_escape_rfc3986
    assert_equal "%20", SnsMultipost::OAuth1.escape(" ")
    assert_equal "%21", SnsMultipost::OAuth1.escape("!")
    assert_equal "~", SnsMultipost::OAuth1.escape("~")
    assert_equal "-._~", SnsMultipost::OAuth1.escape("-._~")
    assert_equal "%E3%81%82", SnsMultipost::OAuth1.escape("あ") # UTF-8 バイト単位
  end

  def test_known_answer_signature_matches_x_docs_example
    header = SnsMultipost::OAuth1.authorization_header(
      method: "POST",
      url: "https://api.twitter.com/1.1/statuses/update.json",
      consumer_key: KNOWN_CONSUMER_KEY, consumer_secret: KNOWN_CONSUMER_SECRET,
      token: KNOWN_TOKEN, token_secret: KNOWN_TOKEN_SECRET,
      query_params: { "status" => "Hello Ladies + Gentlemen, a signed OAuth request!",
                      "include_entities" => "true" },
      nonce: KNOWN_NONCE, timestamp: KNOWN_TIMESTAMP)
    # ヘッダ内の oauth_signature は escape 済み（+ → %2B, = → %3D）
    assert_includes header, "oauth_signature=\"#{SnsMultipost::OAuth1.escape(KNOWN_SIGNATURE)}\""
    assert header.start_with?("OAuth ")
    %w[oauth_consumer_key oauth_nonce oauth_signature_method
       oauth_timestamp oauth_token oauth_version].each do |k|
      assert_includes header, "#{k}=\""
    end
    assert_includes header, "oauth_signature_method=\"HMAC-SHA1\""
    assert_includes header, "oauth_version=\"1.0\""
  end

  def test_header_excludes_request_params
    header = SnsMultipost::OAuth1.authorization_header(
      method: "POST", url: "https://api.twitter.com/2/tweets",
      consumer_key: "ck", consumer_secret: "cs", token: "tk", token_secret: "ts",
      query_params: { "should_not_appear" => "1" },
      nonce: "n", timestamp: "1")
    refute_includes header, "should_not_appear"
  end
end
