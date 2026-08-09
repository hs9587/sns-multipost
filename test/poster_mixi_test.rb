require_relative "test_helper"
require "config"
require "poster/mixi"

class PosterMixiTest < Minitest::Test
  class FakeClient
    attr_reader :text, :media_paths, :failure_screenshot_path

    def post(text:, media_paths:, failure_screenshot_path: nil)
      @text = text
      @media_paths = media_paths
      @failure_screenshot_path = failure_screenshot_path
      { posted: true, url: "https://mixi.jp/view_voice.pl?id=123" }
    end
  end

  Job = Struct.new(:sns, :text, :title, :media_paths, :path, keyword_init: true)

  def config(dry_run: false)
    SnsMultipost::Config.new("dry_run" => dry_run)
  end

  def test_posts_150_graphemes_and_only_first_image
    Dir.mktmpdir do |dir|
      first = File.join(dir, "one.png")
      second = File.join(dir, "two.jpg")
      File.binwrite(first, "png")
      File.binwrite(second, "jpg")
      client = FakeClient.new
      job = Job.new(sns: "mixi", text: "あ" * 200, media_paths: [first, second])

      result = SnsMultipost::Poster::Mixi.new(config, client: client).perform(job)

      assert_equal 150, client.text.grapheme_clusters.length
      assert client.text.end_with?("…")
      assert_equal [first], client.media_paths
      assert result[:posted]
    end
  end

  def test_rejects_unsupported_image_before_opening_browser
    Dir.mktmpdir do |dir|
      image = File.join(dir, "one.webp")
      File.binwrite(image, "webp")
      client = FakeClient.new
      job = Job.new(sns: "mixi", text: "本文", media_paths: [image])

      error = assert_raises(RuntimeError) do
        SnsMultipost::Poster::Mixi.new(config, client: client).perform(job)
      end

      assert_match(/JPEGまたはPNG/, error.message)
      assert_nil client.text
    end
  end

  def test_registered_in_registry
    assert_equal SnsMultipost::Poster::Mixi,
                 SnsMultipost::Poster::REGISTRY["mixi"]
  end
end
