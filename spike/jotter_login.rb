# frozen_string_literal: true
# スパイク: 専用プロファイルで Jotter.me のログイン（セーブポイント）が
# 次回起動でも保たれるかを確認する（投稿はしない・使い捨て）。
#
# 手動ログインの最中に ferrum で生ページを触ると CDP がハングするため、
# ログイン/確認は「素の Chrome を専用プロファイルで起動して目視」で行い、
# クッキー数だけを headless の ferrum で後から覗く（ここは手動干渉なしで安全）。
#
# 使い方（ご自分のターミナルで）:
#   1回目（ログイン）:  ruby spike/jotter_login.rb login
#     → 素の Chrome が開く → Jotter にログイン（セーブポイントURLをアドレスバーへ）
#     → ログインできたら Chrome の窓を閉じる（プロファイルが確定保存される）
#   2回目（永続確認）:  ruby spike/jotter_login.rb check
#     → 同じプロファイルで素の Chrome が開く → ログイン状態が残っているか目視
#     → 窓を閉じる
#   クッキー数だけ見る:  ruby spike/jotter_login.rb cookies
#     → headless で起動しプロファイルのクッキー数・ドメインを表示（値は出さない）
#
# 何も引数が無ければ login 扱い。

require "fileutils"

CHROME  = "C:/Program Files/Google/Chrome/Application/chrome.exe"
PROFILE = File.expand_path("../state/browser/jotter", __dir__)
JOTTER  = "https://jotter.me/"

FileUtils.mkdir_p(PROFILE)

mode = (ARGV[0] || "login").downcase

# 素の Chrome を専用プロファイルで開き、ユーザーが窓を閉じるまで待つ。
def open_chrome_and_wait(url)
  args = [
    "--user-data-dir=#{PROFILE}",
    "--no-first-run",
    "--no-default-browser-check",
    url,
  ]
  pid = spawn(CHROME, *args)
  puts "  Chrome 起動（pid=#{pid}）。ログイン/確認が済んだら Chrome の窓を閉じてください。"
  Process.wait(pid)
  puts "  Chrome が閉じられました（プロファイル保存済み）。"
rescue Errno::ECHILD
  # 既存 Chrome にハンドオフして即 return するケース。窓を閉じたら Enter で続行。
  puts "  （Chrome が別プロセスに委譲した可能性）。窓を閉じたら Enter を押してください..."
  $stdin.gets
end

case mode
when "login"
  puts "[login] 専用プロファイル: #{PROFILE}"
  puts "[login] Jotter にログイン（セーブポイント方式ならアドレスバーにセーブポイントURLを貼る）。"
  open_chrome_and_wait(JOTTER)
  puts "[login] 終了。次に `ruby spike/jotter_login.rb check` で永続を確認。"
  puts "[login] クッキーだけ見るなら `ruby spike/jotter_login.rb cookies`。"

when "check"
  puts "[check] 同じプロファイルで開きます。ログイン状態が残っているか目視してください。"
  open_chrome_and_wait(JOTTER)
  puts "[check] 目視の結論（ログイン後の画面か／ログイン前に戻ったか）を教えてください。"

when "cookies"
  # ここは手動干渉が無いので ferrum を headless で使ってもハングしにくい。
  require "ferrum"
  puts "[cookies] headless でプロファイルを読み込み、クッキーを集計します（値は表示しません）。"
  browser = Ferrum::Browser.new(
    browser_path: CHROME,
    headless: true,
    user_data_dir: PROFILE,
    timeout: 30,
    process_timeout: 60)
  begin
    all = browser.cookies.all.values
    puts "[cookies] クッキー総数: #{all.size}"
    by_domain = all.group_by(&:domain).transform_values(&:size)
    by_domain.sort_by { |_, n| -n }.each do |dom, n|
      puts "  #{dom}: #{n}"
    end
  rescue => e
    puts "[cookies] 取得失敗: #{e.class}: #{e.message}"
  ensure
    browser.quit
  end

else
  warn "usage: ruby spike/jotter_login.rb [login|check|cookies]"
  exit 1
end
