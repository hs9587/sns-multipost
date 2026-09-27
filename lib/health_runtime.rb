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

      http_healthy?(state, timeout: timeout)
    rescue ArgumentError, TypeError
      false
    end

    def http_healthy?(state, timeout: 0.5)
      address = state["resolved_ip"].to_s
      port = Integer(state["port"])
      return false if address.empty?

      Socket.tcp(address, port, connect_timeout: timeout) do |socket|
        socket.write("HEAD /ping HTTP/1.1\r\nHost: #{address}:#{port}\r\nConnection: close\r\n\r\n")
        return false unless IO.select([socket], nil, nil, timeout)

        return socket.gets.to_s.match?(%r{\AHTTP/1\.[01] 200\b})
      end
      false
    rescue ArgumentError, TypeError, SystemCallError, IOError
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
