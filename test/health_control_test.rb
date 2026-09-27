require_relative "test_helper"
require "health_control"

class HealthControlTest < Minitest::Test
  FakeStatus = Struct.new(:success?, :exitstatus)

  def test_stop_cleans_stale_state_when_recorded_process_is_already_gone
    Dir.mktmpdir do |root|
      SnsMultipost::HealthRuntime.save(root, {
        "selector" => "nebula",
        "resolved_ip" => "127.0.0.1",
        "port" => 1,
        "pid" => 999_999
      })
      capture3 = lambda do |*args|
        assert_equal "taskkill.exe", args.first
        ["", "process not found", FakeStatus.new(false, 128)]
      end
      control = SnsMultipost::HealthControl.new(root: root, capture3: capture3)
      control.define_singleton_method(:registered?) { false }

      assert control.stop

      assert_empty SnsMultipost::HealthRuntime.load(root)
    end
  end
end
