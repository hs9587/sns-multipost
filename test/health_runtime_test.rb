require_relative "test_helper"
require "health_runtime"

class HealthRuntimeTest < Minitest::Test
  def test_saves_loads_and_removes_only_matching_process_state
    Dir.mktmpdir do |root|
      state = {
        "selector" => "nebula", "resolved_ip" => "10.99.0.5",
        "port" => 8765, "pid" => 123
      }
      SnsMultipost::HealthRuntime.save(root, state)
      assert_equal state, SnsMultipost::HealthRuntime.load(root)
      refute SnsMultipost::HealthRuntime.remove(root, pid: 999)
      assert SnsMultipost::HealthRuntime.remove(root, pid: 123)
      assert_empty SnsMultipost::HealthRuntime.load(root)
    end
  end

  def test_summary_marks_unreachable_saved_server_as_stopped
    Dir.mktmpdir do |root|
      SnsMultipost::HealthRuntime.save(root, {
        "selector" => "home", "resolved_ip" => "127.0.0.1",
        "port" => 1, "pid" => 123
      })

      output = SnsMultipost::HealthRuntime.summary(root)
      assert_includes output, "停止中"
      assert_includes output, "home 127.0.0.1:1"
    end
  end
end
