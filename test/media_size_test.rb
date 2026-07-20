require_relative "test_helper"
require "media"

class MediaSizeTest < Minitest::Test
  def with_files
    Dir.mktmpdir do |dir|
      small = File.join(dir, "small.jpg")
      big   = File.join(dir, "big.jpg")
      File.binwrite(small, "x" * 100)
      File.binwrite(big, "x" * 2_000_000)
      yield small, big
    end
  end

  def test_no_size_limit_sns_keeps_all
    with_files do |small, big|
      assert_equal [small, big], SnsMultipost::Media.within_size([small, big], "tumblr")
    end
  end

  def test_bluesky_drops_oversized
    with_files do |small, big|
      assert_equal [small], SnsMultipost::Media.within_size([small, big], "bluesky")
    end
  end

  def test_logger_called_for_dropped
    with_files do |small, big|
      logged = []
      SnsMultipost::Media.within_size([small, big], "bluesky", logger: ->(m) { logged << m })
      assert_equal 1, logged.size
      assert_includes logged.first, "big.jpg"
    end
  end
end
