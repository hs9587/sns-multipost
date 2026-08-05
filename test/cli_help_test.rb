require_relative "test_helper"
require "open3"
require "rbconfig"

class CliHelpTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  COMMANDS = %w[dryrun_titles post retry run_queue watch whoami].freeze

  def run_cli(command, *args)
    Open3.capture3(
      RbConfig.ruby, File.join(ROOT, "bin", command), *args,
      chdir: ROOT)
  end

  def test_all_commands_support_long_and_short_help
    COMMANDS.each do |command|
      %w[--help -h].each do |flag|
        stdout, stderr, status = run_cli(command, flag)
        assert status.success?, "#{command} #{flag}: #{stderr}"
        assert_includes stdout, "Usage: ruby bin/#{command}"
        assert_empty stderr
      end
    end
  end

  def test_unknown_option_prints_usage_and_exits_two
    _stdout, stderr, status = run_cli("post", "--unknown")
    assert_equal 2, status.exitstatus
    assert_includes stderr, "Usage: ruby bin/post"
  end

  def test_watch_help_describes_sync_only
    stdout, _stderr, status = run_cli("watch", "--help")
    assert status.success?
    assert_includes stdout, "--sync-only"
    assert_includes stdout, "キューを作らず監視基準だけ最新へ進める"
    assert_includes stdout, "この後に ruby bin/run_queue"
  end

  def test_run_queue_help_explains_watch_precondition
    stdout, _stderr, status = run_cli("run_queue", "--help")
    assert status.success?
    assert_includes stdout, "先に ruby bin/watch"
  end

  def test_dryrun_titles_help_explains_dictionary_check_without_posting
    stdout, _stderr, status = run_cli("dryrun_titles", "--help")
    assert status.success?
    assert_includes stdout, "title_rules.yml"
    assert_includes stdout, "各SNSへの投稿は行いません"
  end

  def test_help_is_compact_without_blank_lines_between_sections
    stdout, _stderr, status = run_cli("watch", "--help")
    assert status.success?
    refute_includes stdout, "\n\n"
  end

  def test_post_requires_text
    _stdout, stderr, status = run_cli("post")
    assert_equal 2, status.exitstatus
    assert_includes stderr, "本文を指定してください"
    assert_includes stderr, "Usage: ruby bin/post"
  end

  def test_retry_requires_at_least_one_file
    _stdout, stderr, status = run_cli("retry")
    assert_equal 2, status.exitstatus
    assert_includes stderr, "失敗ジョブのJSONファイルを指定してください"
    assert_includes stderr, "Usage: ruby bin/retry"
  end

  def test_dryrun_titles_rejects_invalid_count
    %w[abc 0 -1].each do |count|
      _stdout, stderr, status = run_cli("dryrun_titles", count)
      assert_equal 2, status.exitstatus
      assert_includes stderr, "COUNTは1以上の整数"
    end
  end

  def test_commands_without_positional_arguments_reject_them_before_running
    %w[run_queue watch whoami].each do |command|
      _stdout, stderr, status = run_cli(command, "extra")
      assert_equal 2, status.exitstatus
      assert_includes stderr, "余分な引数"
      assert_includes stderr, "Usage: ruby bin/#{command}"
    end
  end
end
