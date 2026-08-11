require_relative "test_helper"
require "blogger_image_browser"

class BloggerImageBrowserTest < Minitest::Test
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
    attr_reader :execution_id

    def initialize(urls: nil, input: nil)
      @execution_id = 1
      @urls = urls
      @input = input
    end

    def evaluate(_script) = @urls || []
    def at_css(selector) = selector == 'input[type="file"]' ? @input : nil
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
    attr_reader :goto_url, :selected, :quit_called, :upload_option

    def initialize
      @urls = []
      @image_button = FakeNode.new
      @picker_open = false
      @upload_option = FakeNode.new(on_evaluate: ->(_script) { @picker_open = true })
      @input = FakeNode.new(on_select_file: lambda do |path|
        @selected = path
        @urls << "https://blogger.googleusercontent.com/img/example/s320/photo.png"
      end)
      @editor = FakeFrame.new(urls: @urls)
      @picker = FakeFrame.new(input: @input)
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
end
