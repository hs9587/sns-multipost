require "json"
require "socket"
require_relative "atomic_file"

module SnsMultipost
  module HealthRuntime
    module_function

    STATE_FILE = "health_server.json"

    def path(root)
      File.join(File.expand_path(root), "state", STATE_FILE)
    end

    def load(root)
      JSON.parse(File.read(path(root)))
    rescue Errno::ENOENT, JSON::ParserError
      {}
    end

    def save(root, state)
      AtomicFile.write(path(root), JSON.pretty_generate(state) + "\n")
    end

    def remove(root, pid: nil)
      current = load(root)
      return false if pid && current["pid"].to_i != pid.to_i

      File.delete(path(root)) if File.exist?(path(root))
      true
    end

    def reachable?(state, timeout: 0.5)
      pid = Integer(state["pid"])
      return false unless process_alive?(pid)

      port_open?(state, timeout: timeout)
    rescue ArgumentError, TypeError
      false
    end

    def port_open?(state, timeout: 0.5)
      address = state["resolved_ip"].to_s
      port = Integer(state["port"])
      return false if address.empty?

      Socket.tcp(address, port, connect_timeout: timeout) { |socket| socket.close }
      true
    rescue ArgumentError, TypeError, SystemCallError, IOError
      false
    end

    def process_alive?(pid)
      Process.kill(0, Integer(pid))
      true
    rescue Errno::ESRCH, ArgumentError, TypeError
      false
    rescue Errno::EPERM
      true
    end

    def summary(root)
      state = load(root)
      return "監視サーバー: 停止中" if state.empty?

      label = "#{state['selector']} #{state['resolved_ip']}:#{state['port']}"
      reachable?(state) ? "監視サーバー: 稼働中 #{label}" : "監視サーバー: 停止中（最終: #{label}）"
    end
  end
end
