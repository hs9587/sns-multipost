require_relative "test_helper"
require "atomic_file"

class AtomicFileTest < Minitest::Test
  def test_writes_complete_content_without_leaving_temporary_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "state", "value.txt")

      assert_equal path, SnsMultipost::AtomicFile.write(path, "new value")

      assert_equal "new value", File.binread(path)
      assert_empty Dir[File.join(File.dirname(path), ".*.tmp")]
    end
  end

  def test_replaces_existing_content
    Dir.mktmpdir do |dir|
      path = File.join(dir, "value.txt")
      File.write(path, "old")

      SnsMultipost::AtomicFile.write(path, "new")

      assert_equal "new", File.binread(path)
    end
  end
end
