require_relative "test_helper"
require "browser_profile"

class BrowserProfileTest < Minitest::Test
  def test_builds_isolated_mixi2_chrome_command
    Dir.mktmpdir do |dir|
      chrome = File.join(dir, "chrome.exe")
      File.write(chrome, "")
      profile = SnsMultipost::BrowserProfile.new(root: dir, chrome_path: chrome)

      command = profile.command("mixi2")

      assert_equal chrome, command.first
      assert_includes command, "--user-data-dir=#{File.join(dir, 'state', 'browser', 'mixi2')}"
      assert_equal "https://mixi.social/home", command.last
      assert Dir.exist?(profile.profile_dir("mixi2"))
    end
  end

  def test_builds_isolated_mixi_chrome_command
    Dir.mktmpdir do |dir|
      chrome = File.join(dir, "chrome.exe")
      File.write(chrome, "")
      profile = SnsMultipost::BrowserProfile.new(root: dir, chrome_path: chrome)

      command = profile.command("mixi")

      assert_includes command, "--user-data-dir=#{File.join(dir, 'state', 'browser', 'mixi')}"
      assert_equal "https://mixi.jp/home.pl", command.last
      assert Dir.exist?(profile.profile_dir("mixi"))
    end
  end

  def test_builds_isolated_blogger_chrome_command
    Dir.mktmpdir do |dir|
      chrome = File.join(dir, "chrome.exe")
      File.write(chrome, "")
      profile = SnsMultipost::BrowserProfile.new(root: dir, chrome_path: chrome)

      command = profile.command("blogger")

      assert_includes command, "--user-data-dir=#{File.join(dir, 'state', 'browser', 'blogger')}"
      assert_equal "https://www.blogger.com/", command.last
      assert Dir.exist?(profile.profile_dir("blogger"))
    end
  end

  def test_rejects_unknown_service
    Dir.mktmpdir do |dir|
      profile = SnsMultipost::BrowserProfile.new(root: dir, chrome_path: "missing")

      error = assert_raises(ArgumentError) { profile.command("unknown") }
      assert_match(/未対応のSNS/, error.message)
    end
  end
end
