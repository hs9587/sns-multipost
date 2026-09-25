require_relative "test_helper"
require "health_network"

class HealthNetworkTest < Minitest::Test
  INTERFACES = [
    { "name" => "nebula1", "ipv4" => ["10.99.0.5"], "gateways" => [] },
    { "name" => "Wi-Fi", "ipv4" => ["192.168.1.20"], "gateways" => ["192.168.1.1"] },
    { "name" => "vEthernet (WSL)", "ipv4" => ["172.28.144.1"], "gateways" => [] }
  ].freeze

  def test_resolves_nebula_by_adapter_name
    result = SnsMultipost::HealthNetwork.resolve("nebula", interfaces: INTERFACES)

    assert_equal "10.99.0.5", result.fetch("address")
    assert_equal "nebula1", result.fetch("interface")
    assert_equal "nebula", result.fetch("kind")
  end

  def test_resolves_private_home_interface_with_default_gateway
    result = SnsMultipost::HealthNetwork.resolve(
      "home", interfaces: INTERFACES, profile_lookup: ->(_name) { "Private" })

    assert_equal "192.168.1.20", result.fetch("address")
    assert_equal "Wi-Fi", result.fetch("interface")
    assert_equal "home", result.fetch("kind")
  end

  def test_refuses_public_home_network
    error = assert_raises(RuntimeError) do
      SnsMultipost::HealthNetwork.resolve(
        "home", interfaces: INTERFACES, profile_lookup: ->(_name) { "Public" })
    end

    assert_includes error.message, "パブリック"
    assert_includes error.message, "プライベート"
  end

  def test_explicit_ip_must_belong_to_this_computer
    result = SnsMultipost::HealthNetwork.resolve("10.99.0.5", interfaces: INTERFACES)
    assert_equal "nebula", result.fetch("kind")

    error = assert_raises(RuntimeError) do
      SnsMultipost::HealthNetwork.resolve("192.168.1.99", interfaces: INTERFACES)
    end
    assert_includes error.message, "割り当てられていない"
  end

  def test_refuses_all_interface_address
    error = assert_raises(RuntimeError) do
      SnsMultipost::HealthNetwork.resolve("0.0.0.0", interfaces: INTERFACES)
    end
    assert_includes error.message, "全インターフェース公開"
  end

  def test_parses_windows_ipconfig_adapters
    text = <<~TEXT
      Unknown adapter nebula1:
         IPv4 Address. . . . . . . . . . . : 10.99.0.5
         Default Gateway . . . . . . . . . :
      Wireless LAN adapter Wi-Fi:
         IPv4 Address. . . . . . . . . . . : 192.168.1.20
         Default Gateway . . . . . . . . . : 192.168.1.1
    TEXT

    interfaces = SnsMultipost::HealthNetwork.parse_ipconfig(text)
    assert_equal %w[nebula1 Wi-Fi], interfaces.map { |item| item.fetch("name") }
    assert_equal ["192.168.1.1"], interfaces.last.fetch("gateways")
  end
end
