require_relative "test_helper"
require "config"
require "poster/jotter"

class PosterJotterTest < Minitest::Test
  class FakeClient
    attr_reader :text, :failure_screenshot_path

    def post(text:, failure_screenshot_path: nil)
      @text = text
      @failure_screenshot_path = failure_screenshot_path
      { posted: true, url: "https://jotter.me/ja-JP/jot/#new" }
    end
  end

  Job = Struct.new(:sns, :text, :title, :media_paths, :path, keyword_init: true)

  def config(dry_run: false)
    SnsMultipost::Config.new("dry_run" => dry_run)
  end

  def test_posts_text_and_ignores_media_for_v1
    client = FakeClient.new
    job = Job.new(sns: "jotter", text: "本文", media_paths: ["one.jpg"])
    result = SnsMultipost::Poster::Jotter.new(config, client: client).perform(job)

    assert_equal "本文", client.text
    assert result[:posted]
  end

  def test_dry_run_does_not_open_browser
    client = FakeClient.new
    job = Job.new(sns: "jotter", text: "本文", media_paths: [])
    result = SnsMultipost::Poster::Jotter.new(
      config(dry_run: true), client: client).post(job)

    assert result[:dry_run]
    assert_nil client.text
  end

  def test_failure_screenshot_path
    Dir.mktmpdir do |dir|
      client = FakeClient.new
      job_path = File.join(dir, "queue", "20260809-170000_jotter_abcd.json")
      job = Job.new(sns: "jotter", text: "本文", media_paths: [], path: job_path)
      SnsMultipost::Poster::Jotter.new(config, client: client).perform(job)

      assert_equal File.join(dir, "failed", "20260809-170000_jotter_abcd.png"),
                   client.failure_screenshot_path
    end
  end

  def test_registered
    assert_equal SnsMultipost::Poster::Jotter,
                 SnsMultipost::Poster::REGISTRY["jotter"]
  end
end
