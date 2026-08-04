require_relative "test_helper"
require "media"

class MediaSizeTest < Minitest::Test
  def with_files
    Dir.mktmpdir do |dir|
      small    = File.join(dir, "small.jpg")
      boundary = File.join(dir, "boundary.jpg")
      big      = File.join(dir, "big.jpg")
      File.binwrite(small, "x" * 100)
      File.binwrite(boundary, "x" * 2_000_000)
      File.binwrite(big, "x" * 2_000_001)
      yield small, boundary, big
    end
  end

  def test_no_size_limit_sns_keeps_all
    with_files do |small, boundary, big|
      assert_equal [small, boundary, big],
                   SnsMultipost::Media.within_size([small, boundary, big], "tumblr")
    end
  end

  def test_bluesky_accepts_two_megabytes_and_drops_larger_files
    with_files do |small, boundary, big|
      assert_equal [small, boundary],
                   SnsMultipost::Media.within_size([small, boundary, big], "bluesky")
    end
  end

  def test_logger_called_for_dropped
    with_files do |small, boundary, big|
      logged = []
      SnsMultipost::Media.within_size(
        [small, boundary, big], "bluesky", logger: ->(m) { logged << m })
      assert_equal 1, logged.size
      assert_includes logged.first, "big.jpg"
      assert_includes logged.first, "2000000"
    end
  end
end
