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

  def test_reachable_requires_the_recorded_process_to_exist
    refute SnsMultipost::HealthRuntime.reachable?({
      "resolved_ip" => "127.0.0.1", "port" => 1, "pid" => 999_999
    })
    assert SnsMultipost::HealthRuntime.process_alive?(Process.pid)
  end

  def test_http_health_check_requires_ping_response
    server = TCPServer.new("127.0.0.1", 0)
    worker = Thread.new do
      socket = server.accept
      request = socket.readpartial(1024)
      assert_includes request, "HEAD /ping HTTP/1.1"
      socket.write("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
      socket.close
    end

    assert SnsMultipost::HealthRuntime.http_healthy?({
      "resolved_ip" => "127.0.0.1", "port" => server.addr[1]
    }, timeout: 1)
  ensure
    worker&.join(1)
    server&.close
  end
end
