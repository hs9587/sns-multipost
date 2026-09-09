require_relative "test_helper"
require "blogger_image_browser"

class BloggerImageBrowserTest < Minitest::Test
  class TransientNoExecutionContextError < StandardError; end

  class FakeNode
    attr_reader :evaluations, :clicks

    def initialize(on_click: nil, on_evaluate: nil, on_select_file: nil)
      @on_click = on_click
      @on_evaluate = on_evaluate
      @on_select_file = on_select_file
      @evaluations = []
      @clicks = 0
    end

    def evaluate(script)
      @evaluations << script
      @on_evaluate&.call(script)
      true
    end

    def click
      @clicks += 1
      @on_click&.call
      self
    end
    def select_file(path) = (@on_select_file&.call(path); self)
  end

  class FakeFrame
    attr_reader :execution_id, :url

    def initialize(url:, urls: nil, input: nil, insert: nil)
      @execution_id = 1
      @url = url
      @urls = urls
      @input = input
      @insert = insert
    end

    def evaluate(_script) = @urls || []
    def at_css(selector) = selector == 'input[type="file"]' ? @input : nil
    def xpath(selector) = selector == SnsMultipost::BloggerImageBrowser::PICKER_INSERT_XPATH ? [@insert].compact : []
  end

  class FakePage
    def command(_name)
      { "frameTree" => { "frame" => { "id" => "main", "url" => "https://www.blogger.com/" },
                           "childFrames" => [
                             { "frame" => { "id" => "picker", "url" => "https://docs.google.com/picker" } }
                           ] } }
    end
  end

  class FakeBrowser
    attr_reader :goto_url, :selected, :quit_called, :upload_option, :insert_button

    def initialize(context_lost_on_insert: false)
      @urls = []
      @image_button = FakeNode.new
      @picker_open = false
      @upload_option = FakeNode.new(on_evaluate: ->(_script) { @picker_open = true })
      @input = FakeNode.new(on_select_file: lambda do |path|
        @selected = path
      end)
      @insert_button = FakeNode.new(on_evaluate: lambda do |script|
        next unless script == "this.click()"

        @urls << "https://blogger.googleusercontent.com/img/example/s320/photo.png"
        @picker_open = false
        raise TransientNoExecutionContextError, "frame closed" if context_lost_on_insert
      end)
      @editor = FakeFrame.new(url: "https://www.blogger.com/editor", urls: @urls)
      @picker = FakeFrame.new(
        url: "https://docs.google.com/picker", input: @input, insert: @insert_button)
    end

    def goto(url) = (@goto_url = url)
    def css(_selector) = [@image_button]
    def xpath(_selector) = [@upload_option]
    def frames = [@editor]
    def page = FakePage.new
    def frame_by(id:) = id == "picker" && @picker_open ? @picker : nil
    def quit = (@quit_called = true)
  end

  def test_upload_returns_original_size_url_and_yields_mapping
    browser = FakeBrowser.new
    yielded = []
    result = SnsMultipost::BloggerImageBrowser.new(
      blog_id: "42", browser: browser, timeout: 0,
      sleeper: ->(_seconds) {}).upload(
        draft_id: "99", media_paths: ["photo.png"]) do |path, url|
          yielded << [path, url]
        end

    expected = "https://blogger.googleusercontent.com/img/example/s0/photo.png"
    assert_equal "https://www.blogger.com/blog/post/edit/42/99", browser.goto_url
    assert_equal "photo.png", browser.selected
    assert_includes browser.upload_option.evaluations, "this.click()"
    assert_equal 0, browser.upload_option.clicks
    assert_includes browser.insert_button.evaluations, "this.click()"
    assert_equal [expected], result
    assert_equal [["photo.png", expected]], yielded
    assert_nil browser.quit_called
  end

  def test_original_url_only_replaces_blogger_size_segment
    assert_equal "https://example.test/s320/a.png",
                 SnsMultipost::BloggerImageBrowser.original_url("https://example.test/s320/a.png")
    assert_equal "https://blogger.googleusercontent.com/x/s0/a.png",
                 SnsMultipost::BloggerImageBrowser.original_url(
                   "https://blogger.googleusercontent.com/x/s640/a.png")
  end

  def test_upload_waits_for_editor_image_when_picker_context_closes_on_insert
    browser = FakeBrowser.new(context_lost_on_insert: true)

    result = SnsMultipost::BloggerImageBrowser.new(
      blog_id: "42", browser: browser, timeout: 0,
      sleeper: ->(_seconds) {}).upload(
        draft_id: "99", media_paths: ["photo.png"])

    assert_equal ["https://blogger.googleusercontent.com/img/example/s0/photo.png"], result
  end
end
