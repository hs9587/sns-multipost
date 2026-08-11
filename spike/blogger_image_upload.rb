#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "browser_profile"
require "ferrum"
require "fileutils"
require "optparse"
require "uri"

options = {}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby spike/blogger_image_upload.rb [options] IMAGE"
  opts.separator "  Bloggerの画像ストアへ画像をアップロードし、恒久URLを表示する実証用スクリプトです。"
  opts.separator "  記事は公開しませんが、画像入りの無題下書きを1件残します。実行後に手動で削除してください。"
  opts.on("--draft-url URL", "既存のBlogger下書きを使う") { |url| options[:draft_url] = url }
  opts.on("-h", "--help", "このヘルプを表示する") do
    puts opts
    exit
  end
end
parser.parse!

if ARGV.size != 1
  warn parser
  exit 2
end

image_path = File.expand_path(ARGV.first)
unless File.file?(image_path)
  warn "画像ファイルが見つかりません: #{image_path}"
  exit 2
end

if options[:draft_url]
  draft_uri = URI(options[:draft_url])
  unless draft_uri.scheme == "https" && draft_uri.host == "www.blogger.com" &&
         draft_uri.path.match?(%r{\A/blog/post/edit/\d+/\d+\z})
    warn "--draft-urlにはBloggerの下書き編集URLを指定してください"
    exit 2
  end
end

profile = SnsMultipost::BrowserProfile.new
browser = Ferrum::Browser.new(
  browser_path: profile.chrome_path,
  browser_options: { "user-data-dir" => profile.profile_dir("blogger") },
  headless: false,
  incognito: false,
  timeout: 20,
  process_timeout: 60,
  pending_connection_errors: false)

wait_for = lambda do |timeout: 20, &block|
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
  loop do
    value = block.call
    break value if value
    break nil if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 0.2
  end
end

flatten_frames = lambda do |node|
  [node.fetch("frame")] + node.fetch("childFrames", []).flat_map { |child| flatten_frames.call(child) }
end

blogger_image_urls = lambda do
  browser.frames.flat_map do |frame|
    next [] unless frame.execution_id

    frame.evaluate(<<~'JS')
      Array.from(document.images)
        .map((image) => image.currentSrc || image.src)
        .filter((url) => url.startsWith('https://blogger.googleusercontent.com/'))
    JS
  rescue Ferrum::Error
    []
  end.uniq
end

begin
  if options[:draft_url]
    browser.goto(options[:draft_url])
    draft_url = options[:draft_url]
  else
    browser.goto("https://www.blogger.com/")
    new_post = wait_for.call do
      browser.css('[aria-label="新しい投稿を作成"]').select do |node|
        node.evaluate("this.getClientRects().length > 0")
      rescue Ferrum::Error
        false
      end.max_by do |node|
        node.evaluate("(() => { const r = this.getBoundingClientRect(); return r.width * r.height; })()")
      end
    end
    unless new_post
      raise "Bloggerにログインしていません。先に ruby bin/browser_login blogger を実行してください"
    end
    new_post.evaluate("this.click()")
    draft_url = wait_for.call do
      browser.url if browser.url.match?(%r{\Ahttps://www\.blogger\.com/blog/post/edit/\d+/\d+})
    end
    raise "Bloggerの新規下書きを開けません" unless draft_url
  end

  image_button = wait_for.call do
    browser.css('[aria-label="画像を挿入"]').find do |node|
      node.evaluate("this.getClientRects().length > 0")
    rescue Ferrum::Error
      false
    end
  end
  raise "Bloggerの画像を挿入ボタンが見つかりません" unless image_button
  image_button.evaluate("this.click()")

  upload_option = wait_for.call do
    browser.xpath("//*[@aria-label='パソコンからアップロード' and @role='menuitem']").find do |node|
      node.evaluate("this.getClientRects().length > 0")
    rescue Ferrum::Error
      false
    end
  end
  raise "Bloggerのパソコンからアップロード項目が見つかりません" unless upload_option
  upload_option.click

  picker = wait_for.call do
    tree = browser.page.command("Page.getFrameTree").fetch("frameTree")
    info = flatten_frames.call(tree).find do |frame|
      frame.fetch("url", "").start_with?("https://docs.google.com/")
    end
    frame = info && browser.frame_by(id: info.fetch("id"))
    frame if frame&.execution_id
  rescue Ferrum::Error
    nil
  end
  raise "Google画像追加画面を確認できません" unless picker

  input = wait_for.call { picker.at_css('input[type="file"]') rescue nil }
  raise "Google画像追加画面のファイル入力が見つかりません" unless input
  before = blogger_image_urls.call
  input.select_file(image_path)

  added = wait_for.call(timeout: 60) do
    urls = blogger_image_urls.call - before
    urls unless urls.empty?
  end
  raise "Blogger本文への画像挿入を確認できません" unless added

  sleep 5
  puts "Blogger image upload spike: ok"
  puts "draft: #{draft_url}"
  added.each do |display_url|
    original_url = display_url.sub(%r{/s\d+/}, "/s0/")
    puts "display: #{display_url}"
    puts "original: #{original_url}"
  end
  puts "記事は公開していません。Bloggerの投稿一覧から無題下書きを手動で削除してください。"
rescue StandardError
  screenshot = File.expand_path("../state/blogger-image-spike-failure.png", __dir__)
  FileUtils.mkdir_p(File.dirname(screenshot))
  browser.screenshot(path: screenshot, full: false) rescue nil
  warn "failure screenshot: #{screenshot}"
  raise
ensure
  browser.quit
end
