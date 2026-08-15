require "fileutils"

module SnsMultipost
  class RunLock
    def initialize(path = File.expand_path("../state/run_queue.lock", __dir__))
      @path = path
    end

    def synchronize
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, File::RDWR | File::CREAT, 0o600) do |file|
        return false unless file.flock(File::LOCK_EX | File::LOCK_NB)

        begin
          file.rewind
          file.truncate(0)
          file.write("pid=#{Process.pid}\n")
          file.flush
          yield
          true
        ensure
          file.flock(File::LOCK_UN)
        end
      end
    end
  end
end
