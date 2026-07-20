require_relative "test_helper"
require "text_limit"

class TextLimitTest < Minitest::Test
  def test_no_limit_sns_returns_as_is
    long = "あ" * 500
    assert_equal long, SnsMultipost::TextLimit.fit(long, "tumblr")
  end

  def test_under_limit_returns_as_is
    assert_equal "短い投稿", SnsMultipost::TextLimit.fit("短い投稿", "bluesky")
  end

  def test_over_limit_truncates_with_ellipsis
    text = "あ" * 400
    got = SnsMultipost::TextLimit.fit(text, "bluesky")
    assert_equal 300, got.grapheme_clusters.length
    assert_equal "あ" * 299 + "…", got
  end

  def test_x_limit_is_280
    text = "b" * 300
    got = SnsMultipost::TextLimit.fit(text, "x")
    assert_equal 280, got.grapheme_clusters.length
    assert got.end_with?("…")
  end

  def test_counts_by_grapheme_not_codepoint
    # 家族絵文字は複数コードポイントで1書記素。上限ちょうどなら切らない
    fam = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}" # 1 grapheme
    text = fam * 300
    got = SnsMultipost::TextLimit.fit(text, "bluesky")
    assert_equal 300, got.grapheme_clusters.length
    assert_equal text, got
  end
end
