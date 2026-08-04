# frozen_string_literal: true
# スパイク: Jotter の投稿フォーム DOM を抽出する。
#
# 判明した事実:
#  - Jotter のログインは「セーブポイントURL」を開くこと自体（セッションは localStorage）。
#  - ferrum は終了時に localStorage をディスクへフラッシュしないため、プロセスをまたいで
#    ログインが保持されない（素の Chrome は正常終了で保持されるが役割が違う）。
#  => 本番ポスターも「毎回 seed（セーブポイントURLを開く）→ そのまま投稿」で行く。
#
# このスパイクも seed と抽出を同一プロセスで行う:
#   export JOTTER_SAVEPOINT='＜セーブポイントURL＞'   # ← この行は共有しない
#   ruby spike/jotter_dom.rb
#
# 秘密（入力値/localStorage/投稿本文）は取らない。要素の構造とラベルのみ。

require "ferrum"
require "json"
require "fileutils"

CHROME  = "C:/Program Files/Google/Chrome/Application/chrome.exe"
PROFILE = File.expand_path("../state/browser/jotter", __dir__)
STATE   = File.expand_path("../state", __dir__)
JOTTER  = "https://jotter.me/"
FileUtils.mkdir_p(STATE)

EXTRACT_JS = <<~'JS'
  (() => {
    const pick = (el) => {
      const r = {
        tag: el.tagName.toLowerCase(),
        type: el.getAttribute('type') || null,
        id: el.id || null,
        name: el.getAttribute('name') || null,
        cls: (el.getAttribute('class') || '').slice(0, 80) || null,
        ph: el.getAttribute('placeholder') || null,
        aria: el.getAttribute('aria-label') || null,
        role: el.getAttribute('role') || null,
        ce: el.getAttribute('contenteditable') || null,
        vis: !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length),
      };
      const isLabel = ['button','a'].includes(r.tag) || r.role === 'button';
      if (isLabel) r.text = (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 40) || null;
      return r;
    };
    const sel = 'textarea, input, button, select, a[href], [contenteditable], [role="textbox"], [role="button"], form';
    const els = Array.from(document.querySelectorAll(sel)).slice(0, 400);
    return { url: location.href, title: document.title, count: els.length, els: els.map(pick) };
  })()
JS

CLICK_TRIGGER_JS = <<~'JS'
  (() => {
    const re = /(投稿|つぶやく|書く|作成|新規|compose|new post|new|post|write)/i;
    const cands = Array.from(document.querySelectorAll('button, a[href], [role="button"]'));
    const hit = cands.find(el => re.test((el.textContent || '') + ' ' + (el.getAttribute('aria-label') || '')));
    if (!hit) return null;
    hit.click();
    return (hit.textContent || hit.getAttribute('aria-label') || '').trim().replace(/\s+/g, ' ').slice(0, 40);
  })()
JS

def evaluate_safe(browser, js)
  browser.evaluate(js)
rescue => e
  puts "  evaluate 失敗: #{e.class}: #{e.message}"
  nil
end

def has_editable?(dump)
  dump["els"].any? { |e| e["tag"] == "textarea" || ["true", ""].include?(e["ce"]) || e["role"] == "textbox" }
end

def fmt(e)
  parts = []
  parts << "<#{e["tag"]}#{e["type"] ? " type=#{e["type"]}" : ""}>"
  parts << "id=#{e["id"]}"       if e["id"]
  parts << "name=#{e["name"]}"   if e["name"]
  parts << "role=#{e["role"]}"   if e["role"]
  parts << "ce=#{e["ce"]}"       if e["ce"]
  parts << "ph=\"#{e["ph"]}\""   if e["ph"]
  parts << "aria=\"#{e["aria"]}\"" if e["aria"]
  parts << "text=\"#{e["text"]}\"" if e["text"]
  parts << "class=#{e["cls"]}"   if e["cls"]
  parts << (e["vis"] ? "[表示]" : "[非表示]")
  parts.join(" ")
end

def print_summary(tag, dump)
  puts "== #{tag} =="
  puts "  URL:   #{dump["url"]}"
  puts "  title: #{dump["title"]}"
  puts "  要素数: #{dump["count"]}"
  puts "  --- 編集欄候補（textarea / contenteditable / role=textbox） ---"
  edit = dump["els"].select { |e| e["tag"] == "textarea" || ["true", ""].include?(e["ce"]) || e["role"] == "textbox" }
  edit.each { |e| puts "    #{fmt(e)}" }
  puts "    （なし）" if edit.empty?
  puts "  --- 送信候補（button / role=button でラベルが投稿・送信系） ---"
  re = /投稿|送信|つぶやく|share|submit|post|送る|公開/i
  snd = dump["els"].select { |e| (e["tag"] == "button" || e["role"] == "button") && re.match?(e["text"].to_s) }
  snd.each { |e| puts "    #{fmt(e)}" }
  puts "    （なし）" if snd.empty?
  puts "  --- input（type別） ---"
  ins = dump["els"].select { |e| e["tag"] == "input" }
  ins.each { |e| puts "    #{fmt(e)}" }
  puts "    （なし）" if ins.empty?
  puts "  --- その他の button / a（ラベルつき・遷移導線の把握用） ---"
  nav = dump["els"].select { |e| ["button", "a"].include?(e["tag"]) && e["text"].to_s != "" }
  nav.first(40).each { |e| puts "    #{fmt(e)}" }
  puts "    （なし）" if nav.empty?
end

# 抽出本体: landing を dump、編集欄が無ければトリガをクリックして再 dump。
def extract_and_report(browser)
  dump1 = evaluate_safe(browser, EXTRACT_JS)
  if dump1
    File.write(File.join(STATE, "jotter_dom_1.json"), JSON.pretty_generate(dump1))
    print_summary("landing", dump1)
  end
  if dump1 && !has_editable?(dump1)
    clicked = evaluate_safe(browser, CLICK_TRIGGER_JS)
    if clicked
      puts "\n[dom] 編集欄が無かったのでトリガをクリック: \"#{clicked}\" → 再抽出"
      sleep 2
      dump2 = evaluate_safe(browser, EXTRACT_JS)
      if dump2
        File.write(File.join(STATE, "jotter_dom_2.json"), JSON.pretty_generate(dump2))
        puts
        print_summary("クリック後", dump2)
      end
    else
      puts "\n[dom] コンポーザーを開くトリガ（投稿/つぶやく系）が見つかりませんでした。"
    end
  end
end

# --- 実行 ---
sp = ENV["JOTTER_SAVEPOINT"].to_s.strip
if sp.empty?
  warn "[dom] 環境変数 JOTTER_SAVEPOINT が未設定です。自分のターミナルで（この行は共有しない）:"
  warn "[dom]   export JOTTER_SAVEPOINT='＜あなたのセーブポイントURL＞'"
  warn "[dom]   ruby spike/jotter_dom.rb"
  exit 1
end

puts "[dom] seed → 同一プロセスで投稿フォームを抽出します（headed / URLは表示しません）。"
browser = Ferrum::Browser.new(
  browser_path: CHROME, headless: false, user_data_dir: PROFILE,
  timeout: 30, process_timeout: 60)
browser.on(:dialog) { |d| d.accept rescue nil }

begin
  browser.goto(sp)  # ferrum 自身がセーブポイントURLを開く（＝ログイン）
  puts "[dom] セーブポイントURLを開きました。"
  puts "[dom] 窓を見て、必要ならページ内ボタン（移行/続ける等）を押してください。"
  puts "[dom] ※アドレスバーでの手動移動はしないでください（CDPがはぐれます）。"
  puts "[dom] あなたの Jotter 画面（投稿できる状態）になったら、この端末で Enter..."
  $stdin.gets

  url = (browser.current_url rescue "?")
  puts "[dom] 現在URL: #{url}"
  if url.include?("/welcome")
    puts "[dom] まだ /welcome です。セーブポイントURLの値・有効性を確認してください。中止します。"
  else
    puts "[dom] 次に、画面の隅にある投稿ボタンを押して【投稿フォームを開いて】ください。"
    puts "[dom] （ページ内のクリックは安全です。アドレスバー移動だけ避ける）"
    puts "[dom] 投稿フォームが開いたら、この端末で Enter..."
    $stdin.gets
    extract_and_report(browser)
  end
ensure
  browser.quit
end
puts "\n[dom] 全量 JSON: state/jotter_dom_1.json（あれば _2.json も）。秘密は含みません。"
