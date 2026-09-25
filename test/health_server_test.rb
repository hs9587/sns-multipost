require_relative "test_helper"
require "health_server"

class HealthServerTest < Minitest::Test
  Request = Struct.new(:request_method, :path)

  def setup
    resolver = lambda do |selector|
      { "selector" => selector, "kind" => "loopback", "interface" => "test", "address" => "127.0.0.1" }
    end
    @root = Dir.mktmpdir
    @server = SnsMultipost::HealthServer.new(
      root: @root, selector: "127.0.0.1", port: 8765,
      network_resolver: resolver,
      clock: -> { Time.new(2026, 9, 26, 8, 0, 0, "+09:00") })
    @snapshot = {
      "status" => "ok", "server_time" => "2026-09-26T08:00:00+09:00",
      "server" => @server.runtime_state,
      "task" => { "State" => "Ready" }, "runner" => {},
      "jobs" => { "latest_done" => nil, "recent_failed_count" => 0, "recent_failed" => [] }
    }
    @server.instance_variable_set(:@snapshot, Struct.new(:value) {
      def build(server_state:)
        value.merge("server" => server_state)
      end
    }.new(@snapshot))
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
  end

  def response_for(method, path)
    response = WEBrick::HTTPResponse.new(WEBrick::Config::HTTP)
    @server.send(:respond, Request.new(method, path), response, @server.runtime_state)
    response
  end

  def test_serves_only_status_html_and_json
    html = response_for("GET", "/")
    assert_equal 200, html.status
    assert_includes html.body, "sns-multipost 状態"
    assert_equal "no-store", html["Cache-Control"]

    json = response_for("GET", "/health.json")
    assert_equal "ok", JSON.parse(json.body).fetch("status")
  end

  def test_rejects_update_methods_and_unknown_paths
    post = response_for("POST", "/")
    assert_equal 405, post.status
    assert_equal "GET, HEAD", post["Allow"]

    hidden = response_for("GET", "/config.yml")
    assert_equal 404, hidden.status
    refute_includes hidden.body, "config.yml"
  end
end
