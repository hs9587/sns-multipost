# lib/oauth1.rb
require "openssl"
require "base64"
require "securerandom"

module SnsMultipost
  module OAuth1
    module_function

    # RFC3986 percent-encoding（バイト単位）
    def escape(value)
      value.to_s.b.gsub(/[^a-zA-Z0-9\-._~]/) { |b| format("%%%02X", b.unpack1("C")) }
    end

    # OAuth1.0a の Authorization ヘッダ値を返す。url はクエリ無しのベースURL。
    # query_params は署名に含める追加パラメータ（JSON/multipart 本文は対象外なので通常 {}）。
    def authorization_header(method:, url:, consumer_key:, consumer_secret:,
                             token:, token_secret:, query_params: {},
                             nonce: SecureRandom.hex(16), timestamp: Time.now.to_i.to_s)
      oauth = {
        "oauth_consumer_key" => consumer_key,
        "oauth_nonce" => nonce.to_s,
        "oauth_signature_method" => "HMAC-SHA1",
        "oauth_timestamp" => timestamp.to_s,
        "oauth_token" => token,
        "oauth_version" => "1.0"
      }
      all = query_params.merge(oauth)
      param_string = all
        .map { |k, v| [escape(k), escape(v)] }
        .sort
        .map { |k, v| "#{k}=#{v}" }
        .join("&")
      base = [method.to_s.upcase, escape(url), escape(param_string)].join("&")
      signing_key = "#{escape(consumer_secret)}&#{escape(token_secret)}"
      signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", signing_key, base))
      header = oauth.merge("oauth_signature" => signature)
      "OAuth " + header.sort.map { |k, v| "#{escape(k)}=\"#{escape(v)}\"" }.join(", ")
    end
  end
end
