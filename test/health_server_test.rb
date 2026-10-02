require_relative "test_helper"
require "health_server"
require "health_snapshot_cache"

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
      "health_task" => { "registered" => true, "State" => "Ready" },
      "task" => { "State" => "Ready" }, "runner" => {},
      "jobs" => { "latest_done" => nil, "recent_failed_count" => 0, "recent_failed" => [] },
      "request" => {
        "started_at" => "2026-09-26T08:00:00+09:00",
        "completed_at" => "2026-09-26T08:00:00+09:00",
        "elapsed_ms" => 125
      }
    }
    SnsMultipost::HealthSnapshotCache.save(@root, @snapshot)
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


  def test_prioritizes_posting_task_and_labels_monitoring_details_clearly
    response = response_for("GET", "/")
    html = response.body

    assert_includes html, "<h2>投稿タスク</h2>"
    assert_includes html, "投稿スケジューラ状態"
    assert_includes html, "投稿スケジューラの前回実行"
    assert_includes html, "投稿スケジューラの次回実行"
    assert_includes html, "投稿処理ラッパー最終"
    assert_includes html, "投稿処理で最後に記録した異常"
    assert_includes html, "完了した投稿ジョブの最新"
    assert_includes html, "未処理の失敗ジョブ"
    assert_includes html, "有効・待機中 (Ready)"
    assert_includes html, "<h2>監視サーバー</h2>"
    assert_includes html, "常時起動用スケジューラ"
    assert_includes html, "登録済み / 有効・待機中 (Ready)"
    assert_includes html, "監視データ取得開始"
    assert_includes html, "監視データ取得完了"
    assert_includes html, "監視データ取得時間"
    refute_includes html, "状態更新開始"
    assert_match(/0\.1[23]秒/, html)
    assert_includes html, "監視サーバー起動日時"
    refute_includes html, "<dt>起動日時</dt>"
    assert_includes html, "画面閲覧開始"
    assert_includes html, "画面受信時刻"
    assert_includes html, "画面表示所要時間"
    assert_operator html.index("<h2>投稿タスク</h2>"), :<, html.index("<h2>監視サーバー</h2>")
    assert_operator html.index("<dt>監視サーバー</dt>"), :<,
                    html.index("<dt>監視サーバー起動日時</dt>")
    assert_includes html, "performance.timeOrigin"
    nonce = response["Content-Security-Policy"][/script-src 'nonce-([^']+)'/, 1]
    refute_nil nonce
    assert_includes html, %Q{<script nonce="#{nonce}">}
    refute_includes response["Content-Security-Policy"], "script-src 'unsafe-inline'"
  end

  def test_uses_compact_definition_list_layout_with_mobile_fallback
    html = response_for("GET", "/").body

    assert_includes html, "dl{display:grid"
    assert_includes html, "grid-template-columns:minmax(14rem,19rem) minmax(0,1fr)"
    assert_includes html, "@media(max-width:42rem)"
    assert_includes html, "dl{grid-template-columns:1fr"
  end

  def test_labels_unregistered_health_scheduler
    @snapshot["health_task"] = {
      "TaskName" => "sns-multipost-health", "registered" => false
    }
    SnsMultipost::HealthSnapshotCache.save(@root, @snapshot)

    html = response_for("GET", "/").body

    assert_includes html, "常時起動用スケジューラ"
    assert_includes html, "未登録"
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
    response = response_for("GET", "/favicon.ico")

    assert_equal 404, response.status
  end

  def test_ping_does_not_query_operational_status
    response = response_for("HEAD", "/ping")

    assert_equal 200, response.status
    assert_equal "text/plain; charset=utf-8", response["Content-Type"]
  end

  def test_status_page_uses_cache_without_querying_operational_status
    state = @server.runtime_state
    SnsMultipost::HealthSnapshotCache.save(
      @root,
      SnsMultipost::HealthSnapshotCache.initial(
        server_state: state,
        now: Time.new(2026, 9, 26, 8, 0, 0, "+09:00")))

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
    SnsMultipost::HealthSnapshotCache.save(@root, @snapshot)

    html = response_for("GET", "/").body

    assert_includes html, "未処理の失敗記録があります（1件）"
    assert_includes html, "再投稿する場合は、重複を避けるため投稿済みでないことを確認してから"
    assert_includes html, "<code>retry</code>してください。"
    refute_includes html, "確認が必要"
  end
end
