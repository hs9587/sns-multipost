# frozen_string_literal: true
# スパイク: Jotter 投稿フォームの詳細を詰める（ポスター実装前の最終確認）。
# full goto は realtime アプリを再読込して窓が不安定になり evaluate が壊れる。
# → full goto はせず、アプリ内クリック（クライアント遷移）で開く安定フローで採る。
#
#   1) ログイン後ホームの釦一覧（本番で「コンポーザーを開く釦」を自動クリックするための特定用）
#   2) 公開レベル select の option（値/表示、どれが「公開」か・既定はどれか）
#   3) textarea の maxlength（文字数上限）
#
#   export JOTTER_SAVEPOINT='＜セーブポイントURL＞'   # ← 共有しない
#   ruby spike/jotter_form.rb
#
# 秘密は取らない（属性・ラベル・option テキストのみ）。投稿はしない。

require "ferrum"
require "json"
require "fileutils"

CHROME  = "C:/Program Files/Google/Chrome/Application/chrome.exe"
PROFILE = File.expand_path("../state/browser/jotter", __dir__)
STATE   = File.expand_path("../state", __dir__)
FileUtils.mkdir_p(STATE)

# ホームの可視な操作要素（コンポーザーを開く釦を探す用）
HOME_JS = <<~'JS'
  (() => {
    const els = Array.from(document.querySelectorAll('button, input[type="button"], input[type="image"], [role="button"], a[href]'));
    return els.map(el => ({
      tag: el.tagName.toLowerCase(),
      type: el.getAttribute('type'),
      cls: el.className || null,
      title: el.getAttribute('title'),
      aria: el.getAttribute('aria-label'),
      href: el.getAttribute('href'),
      text: (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 24) || null,
      vis: !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length)
    })).filter(e => e.vis);
  })()
JS

# コンポーザーが開いた状態の詳細
FORM_JS = <<~'JS'
  (() => {
    const ta = document.querySelector('textarea[name="text"]');
    const submit = document.querySelector('button[type="submit"]');
    const selects = Array.from(document.querySelectorAll('select')).map(s => ({
      cls: s.className || null,
      name: s.getAttribute('name'),
      options: Array.from(s.options).map(o => ({
        value: o.value, text: (o.textContent || '').trim(), selected: o.selected
      }))
    }));
    return {
      url: location.href,
      hasComposer: !!ta,
      textarea: ta ? { name: ta.getAttribute('name'), maxlength: ta.getAttribute('maxlength'), cls: ta.className || null } : null,
      selects: selects,
      submit: submit ? { text: (submit.textContent || '').trim(), type: submit.getAttribute('type') } : null,
      buttons: Array.from(document.querySelectorAll('form button, form input[type="submit"]')).map(b => ((b.textContent || b.value) || '').trim()).filter(Boolean)
    };
  })()
JS

def evaluate_safe(browser, js, tries: 5)
  tries.times do
    begin
      return browser.evaluate(js)
    rescue => e
      warn "  evaluate 再試行（#{e.class}）"
      sleep 1
    end
  end
  nil
end

sp = ENV["JOTTER_SAVEPOINT"].to_s.strip
if sp.empty?
  warn "[form] 環境変数 JOTTER_SAVEPOINT が未設定です（この行は共有しない）:"
  warn "[form]   export JOTTER_SAVEPOINT='＜あなたのセーブポイントURL＞'"
  warn "[form]   ruby spike/jotter_form.rb"
  exit 1
end

puts "[form] seed → 安定フロー（full goto しない）でフォーム詳細を採ります（headed）。"
browser = Ferrum::Browser.new(
  browser_path: CHROME, headless: false, user_data_dir: PROFILE,
  timeout: 8, process_timeout: 60, pending_connection_errors: false)
browser.on(:dialog) { |d| d.accept rescue nil }

begin
  browser.goto(sp) rescue warn("  seed goto は load 完了を待たず進みます")
  puts "[form] セーブポイントURLを開きました。あなたの Jotter 画面になったら Enter..."
  puts "[form] （アドレスバー手動移動・full 再読込はしない）"
  $stdin.gets

  # 1) ホームの釦一覧を採取（コンポーザーを開く釦の特定用）
  home = evaluate_safe(browser, HOME_JS)
  if home
    File.write(File.join(STATE, "jotter_home.json"), JSON.pretty_generate(home))
    puts "== ホームの操作要素（コンポーザーを開く釦の候補探し） =="
    home.each do |e|
      next if e["tag"] == "a" && e["href"].to_s.start_with?("http") && e["text"].to_s.length > 0 && !e["href"].to_s.include?("jot")
      desc = []
      desc << "<#{e["tag"]}#{e["type"] ? " type=#{e["type"]}" : ""}>"
      desc << "cls=#{e["cls"]}"     if e["cls"]
      desc << "href=#{e["href"]}"   if e["href"]
      desc << "title=#{e["title"]}" if e["title"]
      desc << "aria=#{e["aria"]}"   if e["aria"]
      desc << "text=#{e["text"].inspect}" if e["text"]
      puts "   #{desc.join(' ')}"
    end
    puts "   （全量: state/jotter_home.json）"
  else
    puts "[form] ホーム採取に失敗。現在URL: #{browser.current_url rescue '?'}"
  end

  # 2) コンポーザーを開いてもらう（クライアント遷移・再読込なし）
  puts "\n[form] 画面の隅の投稿ボタンを押して【投稿フォームを開いて】ください（クリックはOK）。"
  puts "[form] 投稿フォームが開いたら Enter..."
  $stdin.gets

  data = evaluate_safe(browser, FORM_JS)
  if data && data["hasComposer"]
    File.write(File.join(STATE, "jotter_form.json"), JSON.pretty_generate(data))
    puts "== 結果（コンポーザー詳細） =="
    puts "  URL: #{data["url"]}"
    puts "  textarea: name=#{data["textarea"]["name"]} maxlength=#{data["textarea"]["maxlength"].inspect}"
    puts "  送信ボタン: #{data["submit"].inspect}"
    puts "  フォーム内ボタン: #{data["buttons"].inspect}"
    puts "  --- select（公開レベル） ---"
    (data["selects"] || []).each_with_index do |s, i|
      puts "  select##{i} name=#{s["name"].inspect} cls=#{s["cls"].inspect}"
      (s["options"] || []).each do |o|
        puts "     value=#{o["value"].inspect} text=#{o["text"].inspect}#{o["selected"] ? ' <=既定' : ''}"
      end
    end
    puts "  全量: state/jotter_form.json"
  else
    puts "[form] コンポーザー抽出に失敗。現在URL: #{browser.current_url rescue '?'}"
  end
ensure
  browser.quit
end
