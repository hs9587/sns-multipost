require_relative "test_helper"
require "health_server"

class HealthServerTest < Minitest::Test
  Request = Struct.new(:request_method, :path)

  def setup
    resolver = lambda do |selector|
      { "selector" => selector, "kind" => "loopback", "interface" => "test", "address" => "127.0.0.1" }
    end
    @root = Dir.mktmpdir
    monotonic_tick = 100.0
    @server = SnsMultipost::HealthServer.new(
      root: @root, selector: "127.0.0.1", port: 8765,
      network_resolver: resolver,
      clock: -> { Time.new(2026, 9, 26, 8, 0, 0, "+09:00") },
      monotonic_clock: -> { monotonic_tick += 0.125 })
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
    parsed = JSON.parse(json.body)
    assert_equal "ok", parsed.fetch("status")
    assert_equal 125, parsed.dig("request", "elapsed_ms")
  end


  def test_labels_server_start_and_request_timing_clearly
    response = response_for("GET", "/")
    html = response.body

    assert_includes html, "状態更新開始"
    assert_includes html, "状態更新完了"
    assert_includes html, "状態更新時間"
    assert_match(/0\.1[23]秒/, html)
    assert_includes html, "監視サーバー起動日時"
    refute_includes html, "<dt>起動日時</dt>"
    assert_includes html, "閲覧開始時刻"
    assert_includes html, "ページ受信時刻"
    assert_includes html, "閲覧側所要時間"
    assert_includes html, "performance.timeOrigin"
    nonce = response["Content-Security-Policy"][/script-src 'nonce-([^']+)'/, 1]
    refute_nil nonce
    assert_includes html, %Q{<script nonce="#{nonce}">}
    refute_includes response["Content-Security-Policy"], "script-src 'unsafe-inline'"
  end

  def test_rejects_update_methods_and_unknown_paths
    post = response_for("POST", "/")
    assert_equal 405, post.status
    assert_equal "GET, HEAD", post["Allow"]

    hidden = response_for("GET", "/config.yml")
    assert_equal 404, hidden.status
    refute_includes hidden.body, "config.yml"
  end

  def test_unknown_path_does_not_query_operational_status
    @server.instance_variable_set(:@snapshot, Object.new.tap do |snapshot|
      def snapshot.build(server_state:)
        raise "状態照会を実行してはいけません"
      end
    end)

    response = response_for("GET", "/favicon.ico")

    assert_equal 404, response.status
  end

  def test_ping_does_not_query_operational_status
    @server.instance_variable_set(:@snapshot, Object.new.tap do |snapshot|
      def snapshot.build(server_state:)
        raise "状態照会を実行してはいけません"
      end
    end)

    response = response_for("HEAD", "/ping")

    assert_equal 200, response.status
    assert_equal "text/plain; charset=utf-8", response["Content-Type"]
  end

  def test_status_page_uses_cache_without_querying_operational_status
    state = @server.runtime_state
    @server.send(:initialize_snapshot_cache, state)
    @server.instance_variable_set(:@snapshot, Object.new.tap do |snapshot|
      def snapshot.build(server_state:)
        raise "要求処理中に状態照会を実行してはいけません"
      end
    end)

    response = response_for("GET", "/")

    assert_equal 200, response.status
    assert_includes response.body, "状態を取得中です"
  end

  def test_explains_unresolved_failed_jobs_without_assuming_retry
    @snapshot["status"] = "failed"
    @snapshot["jobs"] = {
      "latest_done" => "20260927-065502_tumblr_ok.json",
      "recent_failed_count" => 1,
      "recent_failed" => ["20260927-065502_jotter_failed.json"]
    }

    html = response_for("GET", "/").body

    assert_includes html, "未処理の失敗記録があります（1件）"
    assert_includes html, "再投稿する場合は、重複を避けるため投稿済みでないことを確認してから"
    assert_includes html, "<code>retry</code>してください。"
    refute_includes html, "確認が必要"
  end
end
