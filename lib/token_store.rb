require "json"
require "fileutils"

module SnsMultipost
  class TokenStore
    def initialize(path)
      @path = path
    end

    def load
      return {} unless File.exist?(@path)
      JSON.parse(File.read(@path))
    end

    def save(hash)
      dir = File.dirname(@path)
      FileUtils.mkdir_p(dir)
      tmp = File.join(dir, ".#{File.basename(@path)}.tmp")
      File.write(tmp, JSON.pretty_generate(hash))
      File.rename(tmp, @path)
    end
  end
end
