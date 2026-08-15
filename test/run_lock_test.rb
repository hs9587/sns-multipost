require_relative "test_helper"
require "run_lock"

class RunLockTest < Minitest::Test
  def test_second_runner_skips_while_first_holds_lock
    Dir.mktmpdir do |dir|
      path = File.join(dir, "run.lock")
      second_acquired = nil

      first_acquired = SnsMultipost::RunLock.new(path).synchronize do
        second_acquired = SnsMultipost::RunLock.new(path).synchronize { flunk }
      end

      assert_equal true, first_acquired
      assert_equal false, second_acquired
    end
  end

  def test_lock_can_be_acquired_again_after_release
    Dir.mktmpdir do |dir|
      path = File.join(dir, "run.lock")
      assert SnsMultipost::RunLock.new(path).synchronize { true }
      assert SnsMultipost::RunLock.new(path).synchronize { true }
    end
  end
end
