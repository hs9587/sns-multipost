require_relative "test_helper"
require "config"

class ConfigTest < Minitest::Test
  def test_targets_for_watch_excludes_fedibird
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
      File.write(path, "targets:\n  - fedibird\n")
      assert_equal ["fedibird"], SnsMultipost::Config.load(path).targets_for(:post)
    end
  end
end
