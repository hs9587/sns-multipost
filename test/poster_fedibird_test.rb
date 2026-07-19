require_relative "test_helper"
require "poster/fedibird"
require "job_queue"
require "config"
require "self_posted"

class PosterFedibirdTest < Minitest::Test
  class FakeApi
    attr_reader :posted
    def upload_media(path)
      { "id" => "m-#{File.basename(path)}" }
    end
    def post_status(text, media_ids:)
      @posted = { text: text, media_ids: media_ids }
      { "id" => "99", "url" => "https://fedibird.com/@hs9587/99" }
    end
  end

  def test_registry_returns_fedibird_poster
    config = SnsMultipost::Config.new({})
    poster = SnsMultipost::Poster.for("fedibird", config)
    assert_kind_of SnsMultipost::Poster::Fedibird, poster
  end

  def test_registry_raises_for_unknown_sns
    assert_raises(RuntimeError) do
      SnsMultipost::Poster.for("unknown-sns", SnsMultipost::Config.new({}))
    end
  end

  def test_dry_run_does_not_post
    config = SnsMultipost::Config.new({ "dry_run" => true })
    job = SnsMultipost::Job.new(sns: "fedibird", text: "テスト本文")
    res = SnsMultipost::Poster.for("fedibird", config).post(job)
    assert res[:dry_run]
  end

  def test_perform_uploads_media_posts_and_records_self_posted
    Dir.mktmpdir do |dir|
      config = SnsMultipost::Config.new({ "dry_run" => false })
      api = FakeApi.new
      sp = SnsMultipost::SelfPosted.new(File.join(dir, "sp.txt"))
      poster = SnsMultipost::Poster::Fedibird.new(config, api: api, self_posted: sp)
      job = SnsMultipost::Job.new(sns: "fedibird", text: "本文",
                                  media_paths: ["a.png", "b.png", "c.png", "d.png", "e.png"])
      res = poster.post(job)
      assert_equal "99", res[:id]
      assert_equal %w[m-a.png m-b.png m-c.png m-d.png], api.posted[:media_ids]
      assert sp.include?("99")
    end
  end
end
