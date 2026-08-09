# frozen_string_literal: true
# スパイク: 本番同様「人の Enter 無し」で、正しい2クリック遷移で編集画面を開けるか検証。
#   seed → ログイン準備完了(ポーリング) → 「Jots」(all)クリック → 「メモを作成します」クリック
#        → textarea[name=text] 出現？
# 投稿はしない。「メモを作成します」釦のセレクタ特定が目的。
#
#   # 専用プロファイルへ一度ログイン済みなら、そのまま実行できる
#   # 初回調査だけは JOTTER_SAVEPOINT をローカル環境変数で渡せる
#   ruby spike/jotter_open.rb

require "ferrum"
require "json"

CHROME  = "C:/Program Files/Google/Chrome/Application/chrome.exe"
PROFILE = File.expand_path("../state/browser/jotter", __dir__)
JOTTER  = "https://jotter.me/"

READY_JS = <<~'JS'
  (() => {
    const ready = !location.href.includes('/welcome') &&
      !!document.querySelector('a[href="/ja-JP/wallet/"]') &&
      !!document.querySelector('input[type="image"].user-face');
    return { url: location.href, ready: ready };
  })()
JS

# 「Jots」(all タブ)をクリック
CLICK_JOTS_JS = <<~'JS'
  (() => {
    const el = Array.from(document.querySelectorAll('input[type="button"], button'))
      .find(e => (e.getAttribute('title') || '') === 'Jots' || (e.className || '').split(/\s+/).includes('all'));
    if (!el) return { clicked: false, reason: 'Jots(all) が見つからない' };
    el.click();
    return { clicked: true, title: el.getAttribute('title'), cls: el.className };
  })()
JS

# 「メモを作成します」相当のトリガを探してクリック（title/aria/value/text で照合）
CLICK_CREATE_JS = <<~'JS'
  (() => {
    const re = /(メモを作成|作成します|作成|create|new|compose)/i;
    const hit = (attr) => Array.from(document.querySelectorAll('input[type="button"], button, [role="button"], a'))
      .find(e => re.test((e.getAttribute(attr) || '')));
    const byText = Array.from(document.querySelectorAll('input[type="button"], button, [role="button"], a'))
      .find(e => re.test(((e.textContent || e.value) || '')));
    const el = hit('title') || hit('aria-label') || byText;
    if (!el) return { clicked: false, reason: 'メモを作成 トリガが見つからない' };
    el.click();
    return {
      clicked: true,
      tag: el.tagName.toLowerCase(),
      type: el.getAttribute('type'),
      title: el.getAttribute('title'),
      aria: el.getAttribute('aria-label'),
      cls: el.className,
      text: ((el.textContent || el.value) || '').trim().slice(0, 30)
    };
  })()
JS

# 現在見えている釦一覧（トリガ特定の予備）
BUTTONS_JS = <<~'JS'
  (() => Array.from(document.querySelectorAll('input[type="button"], button, [role="button"]'))
    .filter(e => (e.offsetWidth || e.offsetHeight))
    .map(e => ({ tag: e.tagName.toLowerCase(), type: e.getAttribute('type'),
                 title: e.getAttribute('title'), cls: e.className || null,
                 text: ((e.textContent || e.value) || '').trim().slice(0, 30) || null })))()
JS

HAS_COMPOSER_JS = '!!document.querySelector(\'textarea[name="text"]\')'

def eval_safe(browser, js)
  browser.evaluate(js)
rescue => e
  { "_error" => "#{e.class}: #{e.message}" }
end

sp = ENV["JOTTER_SAVEPOINT"].to_s.strip
start_url = sp.empty? ? JOTTER : sp

puts "[open] seed → 人の介在なしで 2クリック遷移(Jots→メモを作成します)を検証します（headed）。"
browser = Ferrum::Browser.new(
  browser_path: CHROME, headless: false, user_data_dir: PROFILE,
  timeout: 8, process_timeout: 60, pending_connection_errors: false)
browser.on(:dialog) { |d| d.accept rescue nil }

begin
  browser.goto(start_url) rescue warn("  seed goto は load 完了を待たず進みます")

  ready = false
  last_state = nil
  15.times do |i|
    sleep 1
    last_state = eval_safe(browser, READY_JS)
    if last_state.is_a?(Hash) && last_state["ready"]
      ready = true
      puts "[open] ログイン準備完了（#{i + 1}秒）URL: #{last_state["url"]}"
      break
    end
  end
  unless ready
    puts "[open] 15秒で ready 検出できず。中止。"
    puts "[open] 最終状態: #{last_state.inspect}"
    browser.quit
    exit 1
  end

  # 1) Jots(all) をクリック
  jots = eval_safe(browser, CLICK_JOTS_JS)
  puts "[open] Jots(all) クリック: #{jots.inspect}"
  sleep 2

  # 2) 「メモを作成します」をクリック
  create = eval_safe(browser, CLICK_CREATE_JS)
  puts "[open] メモを作成 クリック: #{create.inspect}"

  opened = false
  10.times do
    sleep 1
    opened = (eval_safe(browser, HAS_COMPOSER_JS) == true)
    break if opened
  end
  url = (browser.current_url rescue "?")
  if opened
    puts "[open] === 成功: 編集画面が開いた（textarea[name=text] 出現） ==="
    puts "[open] URL: #{url}"
    puts "[open] コンポーザーを開くトリガ = 上記「メモを作成 クリック」の要素"
  else
    puts "[open] × 編集画面が開かなかった。URL: #{url}"
    puts "[open] 現在見えている釦一覧（トリガ特定用）:"
    btns = eval_safe(browser, BUTTONS_JS)
    (btns.is_a?(Array) ? btns : []).each { |b| puts "   #{b.inspect}" }
  end
ensure
  browser.quit
end
