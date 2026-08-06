require_relative "test_helper"
require "config"

class ConfigTest < Minitest::Test
  def test_targets_for_uses_separate_watch_and_post_lists
    c = SnsMultipost::Config.new(
      { "targets" => {
        "watch" => %w[bluesky tumblr blogger],
        "post" => %w[fedibird bluesky tumblr blogger]
      } }
    )

    assert_equal %w[bluesky tumblr blogger], c.targets_for(:watch)
    assert_equal %w[fedibird bluesky tumblr blogger], c.targets_for(:post)
  end

  def test_targets_for_missing_list_is_empty
    c = SnsMultipost::Config.new({ "targets" => { "watch" => ["bluesky"] } })

    assert_equal [], c.targets_for(:post)
  end

  def test_legacy_targets_array_remains_compatible
    c = SnsMultipost::Config.new({ "targets" => ["fedibird", "x"] })

    assert_equal ["x"], c.targets_for(:watch)
    assert_equal ["fedibird", "x"], c.targets_for(:post)
  end

  def test_bracket_access
    c = SnsMultipost::Config.new({ "dry_run" => true })
    assert_equal true, c[:dry_run]
  end

  def test_load_missing_file_raises
    assert_raises(RuntimeError) { SnsMultipost::Config.load("/no/such/config.yml") }
  end

  def test_load_reads_yaml
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.yml")
      File.write(path, "targets:\n  watch:\n    - bluesky\n  post:\n    - fedibird\n")
      config = SnsMultipost::Config.load(path)

      assert_equal ["bluesky"], config.targets_for(:watch)
      assert_equal ["fedibird"], config.targets_for(:post)
    end
  end
end
