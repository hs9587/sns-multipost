require_relative "test_helper"
require "self_posted"

class SelfPostedTest < Minitest::Test
  def test_record_and_include
    Dir.mktmpdir do |dir|
      sp = SnsMultipost::SelfPosted.new(File.join(dir, "state", "self_posted.txt"))
      refute sp.include?("100")
      sp.record("100")
      sp.record(200)
      assert sp.include?("100")
      assert sp.include?("200")
      refute sp.include?("300")
    end
  end
end
