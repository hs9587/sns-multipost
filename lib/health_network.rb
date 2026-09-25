require "ipaddr"
require "open3"
require "socket"

module SnsMultipost
  module HealthNetwork
    module_function

    LOOPBACK = IPAddr.new("127.0.0.0/8")
    VIRTUAL_NAMES = /nebula|wsl|hyper-v|vethernet|loopback|virtual|vmware|virtualbox/i

    def resolve(selector, interfaces: interface_list, profile_lookup: method(:network_category))
      value = selector.to_s.strip
      raise "待受先をhome、nebula、またはこのPCのIPv4で指定してください" if value.empty?

      case value.downcase
      when "home", "lan"
        resolve_home(value.downcase, interfaces, profile_lookup)
      when "nebula"
        resolve_nebula(interfaces)
      else
        resolve_explicit(value, interfaces)
      end
    end

    def interface_list(output: nil)
      text = output || run_ipconfig
      parse_ipconfig(text)
    end

    def parse_ipconfig(text)
      blocks = []
      current = nil
      text.to_s.each_line do |line|
        if (match = line.match(/\A\s*(?:.*\badapter\s+|.*アダプター\s+)(.+):\s*\z/i))
          current = { "name" => match[1].strip, "ipv4" => [], "gateways" => [] }
          blocks << current
          next
        end
        next unless current

        line.scan(/(?:\d{1,3}\.){3}\d{1,3}/).each do |address|
          next unless valid_ipv4?(address)

          if line.match?(/gateway|ゲートウェイ/i)
            current["gateways"] << address
          elsif line.match?(/IPv4/i)
            current["ipv4"] << address
          end
        end
      end
      blocks.select { |item| item["ipv4"].any? }
    end

    def resolve_home(selector, interfaces, profile_lookup)
      candidates = interfaces.select do |item|
        item["gateways"].any? && !item["name"].match?(VIRTUAL_NAMES) &&
          item["ipv4"].any? { |address| private_ipv4?(address) }
      end
      candidate = one_candidate!(candidates, "家庭内LAN")
      category = profile_lookup.call(candidate.fetch("name"))
      unless category == "Private"
        category_label = { "Public" => "パブリック", "DomainAuthenticated" => "ドメイン" }
                         .fetch(category, category || "種別不明")
        raise "家庭内LAN「#{candidate.fetch('name')}」は#{category_label}です。" \
              "Windowsで信頼できるネットワークをプライベートに設定してください"
      end
      result(selector, candidate, "home")
    end

    def resolve_nebula(interfaces)
      candidates = interfaces.select { |item| item.fetch("name").match?(/nebula/i) }
      result("nebula", one_candidate!(candidates, "Nebula"), "nebula")
    end

    def resolve_explicit(address, interfaces)
      ip = IPAddr.new(address)
      raise "IPv4を指定してください: #{address}" unless ip.ipv4?
      raise "0.0.0.0での全インターフェース公開は許可していません" if address == "0.0.0.0"

      candidate = interfaces.find { |item| item.fetch("ipv4").include?(address) }
      raise "このPCに割り当てられていないIPv4です: #{address}" unless candidate

      kind = if LOOPBACK.include?(ip)
               "loopback"
             elsif candidate.fetch("name").match?(/nebula/i)
               "nebula"
             else
               "explicit"
             end
      result(address, candidate, kind, address: address)
    rescue IPAddr::InvalidAddressError
      raise "正しいIPv4、home、nebulaのいずれかを指定してください: #{address}"
    end

    def result(selector, candidate, kind, address: nil)
      addresses = candidate.fetch("ipv4").reject { |value| value.start_with?("169.254.") }
      raise "#{candidate.fetch('name')}に利用可能なIPv4がありません" if addresses.empty?
      if address.nil? && addresses.length > 1
        raise "#{candidate.fetch('name')}にIPv4が複数あります。IPを直接指定してください"
      end

      {
        "selector" => selector,
        "kind" => kind,
        "interface" => candidate.fetch("name"),
        "address" => address || addresses.first
      }
    end

    def one_candidate!(candidates, label)
      raise "#{label}用のネットワークアダプターが見つかりません" if candidates.empty?
      if candidates.length > 1
        names = candidates.map { |item| item.fetch("name") }.join("、")
        raise "#{label}用の候補が複数あります（#{names}）。IPを直接指定してください"
      end
      candidates.first
    end

    def private_ipv4?(address)
      ip = IPAddr.new(address)
      ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"].any? do |range|
        IPAddr.new(range).include?(ip)
      end
    rescue IPAddr::InvalidAddressError
      false
    end

    def valid_ipv4?(address)
      parts = address.split(".").map { |part| Integer(part, 10) }
      parts.length == 4 && parts.all? { |part| part.between?(0, 255) }
    rescue ArgumentError
      false
    end

    def run_ipconfig
      stdout, stderr, status = Open3.capture3("ipconfig.exe")
      if status.success?
        return stdout.dup.force_encoding(Encoding::Windows_31J)
                     .encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      end

      raise "Windowsのネットワーク情報を取得できません: #{stderr.to_s.strip}"
    end

    def network_category(interface_name)
      escaped = interface_name.gsub("'", "''")
      script = <<~POWERSHELL
        $ErrorActionPreference = 'Stop'
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
        $profile = Get-NetConnectionProfile | Where-Object { $_.InterfaceAlias -eq '#{escaped}' } | Select-Object -First 1
        if ($profile) { $profile.NetworkCategory.ToString() }
      POWERSHELL
      stdout, _stderr, status = Open3.capture3(
        "powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
        "-Command", script)
      value = stdout.to_s.strip
      status.success? && !value.empty? ? value : nil
    end
  end
end
