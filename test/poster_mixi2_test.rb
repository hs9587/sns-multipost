require_relative "test_helper"
require "config"
require "poster/mixi2"

class PosterMixi2Test < Minitest::Test
  class FakeClient
    attr_reader :text, :media_paths, :failure_screenshot_path

    def post(text:, media_paths:, failure_screenshot_path: nil)
      @text = text
      @media_paths = media_paths
      @failure_screenshot_path = failure_screenshot_path
      { posted: true, url: "https://mixi.social/@me/posts/123" }
    end
  end

  Job = Struct.new(:sns, :text, :title, :media_paths, :path, keyword_init: true)

  def config(dry_run: false)
    SnsMultipost::Config.new("dry_run" => dry_run)
  end

  def test_posts_fitted_text_and_first_four_images
    client = FakeClient.new
    job = Job.new(sns: "mixi2", text: "あ" * 200,
                  media_paths: %w[1.jpg 2.jpg 3.jpg 4.jpg 5.jpg])

    result = SnsMultipost::Poster::Mixi2.new(config, client: client).perform(job)

    assert_equal 150, client.text.grapheme_clusters.length
    assert client.text.end_with?("…")
    assert_equal %w[1.jpg 2.jpg 3.jpg 4.jpg], client.media_paths
    assert result[:posted]
  end

  def test_dry_run_does_not_open_browser
    client = FakeClient.new
    job = Job.new(sns: "mixi2", text: "やあ", media_paths: [])

    result = SnsMultipost::Poster::Mixi2.new(
      config(dry_run: true), client: client).post(job)

    assert result[:dry_run]
    assert_nil client.text
  end

  def test_failure_screenshot_is_placed_beside_failed_job
    Dir.mktmpdir do |dir|
      client = FakeClient.new
      job_path = File.join(dir, "queue", "20260809-120000_mixi2_abcd.json")
      job = Job.new(sns: "mixi2", text: "本文", media_paths: [], path: job_path)

      SnsMultipost::Poster::Mixi2.new(config, client: client).perform(job)

      assert_equal File.join(dir, "failed", "20260809-120000_mixi2_abcd.png"),
                   client.failure_screenshot_path
    end
  end

  def test_registered_in_registry
    assert_equal SnsMultipost::Poster::Mixi2,
                 SnsMultipost::Poster::REGISTRY["mixi2"]
  end
end
