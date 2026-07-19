require "fileutils"

module SnsMultipost
  class SelfPosted
    DEFAULT_PATH = File.expand_path("../state/self_posted.txt", __dir__)

    def initialize(path = DEFAULT_PATH)
      @path = path
    end

    def record(id)
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, "a") { |f| f.puts(id) }
    end

    def include?(id)
      File.exist?(@path) && File.readlines(@path, chomp: true).include?(id.to_s)
    end
  end
end
