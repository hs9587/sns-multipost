require_relative "test_helper"
require "open3"
require "rbconfig"
require "cli"

class CliHelpTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  COMMANDS = %w[dryrun_titles post retry run_queue threads_auth watch whoami].freeze

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

  def test_threads_auth_help_explains_two_step_authentication
    stdout, _stderr, status = run_cli("threads_auth", "--help")
    assert status.success?
    assert_includes stdout, "--authorize"
    assert_includes stdout, "--callback"
    assert_includes stdout, "state/threads_token.json"
    assert_includes stdout, "Threadsへ投稿しません"
  end

  def test_help_is_compact_without_blank_lines_between_sections
    stdout, _stderr, status = run_cli("watch", "--help")
    assert status.success?
    refute_includes stdout, "\n\n"
  end

  def test_description_lines_use_the_same_two_space_indent_as_examples_and_notes
    stdout, _stderr, status = run_cli("watch", "--help")
    assert status.success?
    assert_includes stdout,
                    "\n  sns-multipostの入口としてFedibirdの新着を検出し、queue/に投稿ジョブを作成します。\n"
    assert_includes stdout,
                    "\n  通常はこの後に ruby bin/run_queue を実行して、各SNSへ投稿します。\n"
    assert_includes stdout, "\n  ruby bin/watch\n"
    assert_includes stdout, "\n  このコマンドだけでは各SNSへの投稿は実行しません。\n"
  end

  def test_post_uses_default_text_when_text_is_omitted
    assert_equal "おはようございます",
                 SnsMultipost::Cli.text_or_default([], default: "おはようございます")
    assert_equal "任意の 本文",
                 SnsMultipost::Cli.text_or_default([" 任意の", "本文 "], default: "おはようございます")
  end

  def test_post_help_describes_default_text
    stdout, _stderr, status = run_cli("post", "--help")
    assert status.success?
    assert_includes stdout, "Usage: ruby bin/post [options] [TEXT...]"
    assert_includes stdout, "TEXTを省略した場合、本文は「おはようございます」になります。"
    assert_includes stdout, "ruby bin/post"
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
