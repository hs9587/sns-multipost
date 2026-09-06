require "fileutils"
require "securerandom"

module SnsMultipost
  module AtomicFile
    module_function

    def write(path, content)
      directory = File.dirname(path)
      FileUtils.mkdir_p(directory)
      temporary = File.join(
        directory, ".#{File.basename(path)}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp")
      File.open(temporary, "wb") do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      path
    ensure
      File.delete(temporary) if temporary && File.exist?(temporary)
    end
  end
end
