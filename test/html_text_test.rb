require_relative "test_helper"
require "html_text"

class HtmlTextTest < Minitest::Test
  def test_to_text
    html = "<p>おはよう<br />今日は<a href=\"#\">リンク</a>です</p><p>二段落目 &amp; 記号</p>"
    assert_equal "おはよう\n今日はリンクです\n\n二段落目 & 記号",
                 SnsMultipost::HtmlText.to_text(html)
  end

  def test_plain_text_passes_through
    assert_equal "そのまま", SnsMultipost::HtmlText.to_text("そのまま")
  end
end
