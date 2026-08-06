require_relative "test_helper"
require "config"
require "poster/threads"

class PosterThreadsTest < Minitest::Test
  class FakeApi
    attr_reader :text
    def create_text_post(text)
      @text = text
      { "id" => "777" }
    end
  end

  class EmptyApi
    def create_text_post(_text) = {}
  end

  Job = Struct.new(:sns, :text, :title, :media_paths, keyword_init: true)

  def config(dry_run: false)
    SnsMultipost::Config.new(
      "dry_run" => dry_run,
      "threads" => { "access_token" => "TOK" })
  end

  def job(text: "やあ")
    Job.new(sns: "threads", text: text, title: nil, media_paths: [])
  end

  def test_perform_posts_text_and_returns_id
    api = FakeApi.new
    result = SnsMultipost::Poster::Threads.new(config, api: api).perform(job(text: "やあ"))

    assert_equal "やあ", api.text
    assert_equal "777", result[:id]
  end

  def test_truncates_over_limit_text
    api = FakeApi.new
    SnsMultipost::Poster::Threads.new(config, api: api).perform(job(text: "あ" * 600))

    assert_equal 500, api.text.grapheme_clusters.length
    assert api.text.end_with?("…")
  end

  def test_missing_post_id_raises
    poster = SnsMultipost::Poster::Threads.new(config, api: EmptyApi.new)

    error = assert_raises(RuntimeError) { poster.perform(job) }
    assert_match(/投稿IDがありません/, error.message)
  end

  def test_dry_run_does_not_call_api
    api = FakeApi.new
    result = SnsMultipost::Poster::Threads.new(config(dry_run: true), api: api).post(job)

    assert result[:dry_run]
    assert_nil api.text
  end

  def test_registered_in_registry
    assert_equal SnsMultipost::Poster::Threads,
                 SnsMultipost::Poster::REGISTRY["threads"]
  end
end
