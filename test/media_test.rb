require_relative "test_helper"
require "media"

class MediaTest < Minitest::Test
  def test_download_with_injected_fetcher
    Dir.mktmpdir do |dir|
      fetcher = ->(url) { "data-of-#{url}" }
      paths = SnsMultipost::Media.download(
        ["https://example.com/a.png", "https://example.com/b.jpeg"],
        dir, fetcher: fetcher)
      assert_equal ["01.png", "02.jpeg"], paths.map { |p| File.basename(p) }
      assert_equal "data-of-https://example.com/a.png", File.binread(paths[0])
    end
  end

  def test_limit_for
    assert_equal 1, SnsMultipost::Media.limit_for("mixi")
    assert_equal 4, SnsMultipost::Media.limit_for("fedibird")
    assert_equal 0, SnsMultipost::Media.limit_for("jotter")
  end

  def test_for_sns_truncates
    assert_equal %w[a], SnsMultipost::Media.for_sns(%w[a b c], "mixi")
    assert_equal %w[a b c d], SnsMultipost::Media.for_sns(%w[a b c d e], "x")
  end
end
