defmodule MdnsLite.InfoTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias MdnsLite.Info

  test "tables match config" do
    out = capture_io(&Info.dump_records/0)

    {:ok, name} = :inet.gethostname()

    # The lines aren't in guaranteed to be in this order, so check one by one
    assert out =~ "<interface_ipv4>.in-addr.arpa: type PTR, class IN, ttl 120, #{name}.local"
    assert out =~ "<interface_ipv6>.ip6.arpa: type PTR, class IN, ttl 120, #{name}.local"

    assert out =~
             "#{name}._http._tcp.local: type SRV, class IN, ttl 120, priority 0, weight 0, port 80, #{name}.local."

    assert out =~ "#{name}._http._tcp.local: type TXT, class IN, ttl 120, key=value"

    assert out =~
             "#{name}._ssh._tcp.local: type SRV, class IN, ttl 120, priority 0, weight 0, port 22, #{name}.local."

    assert out =~ "#{name}._ssh._tcp.local: type TXT, class IN, ttl 120"
    assert out =~ "#{name}.local: type A, class IN, ttl 120, addr <interface_ipv4>"
    assert out =~ "#{name}.local: type AAAA, class IN, ttl 120, addr <interface_ipv6>"
    assert out =~ "_http._tcp.local: type PTR, class IN, ttl 120, #{name}._http._tcp.local"
    assert out =~ "_services._dns-sd._udp.local: type PTR, class IN, ttl 120, _http._tcp.local"
    assert out =~ "_services._dns-sd._udp.local: type PTR, class IN, ttl 120, _ssh._tcp.local"
    assert out =~ "_ssh._tcp.local: type PTR, class IN, ttl 120, #{name}._ssh._tcp.local"
    assert out =~ "nerves.local: type A, class IN, ttl 120, addr <interface_ipv4>"
    assert out =~ "nerves.local: type AAAA, class IN, ttl 120, addr <interface_ipv6>"

    line_count = out |> String.split("\n") |> length()
    assert line_count == 16
  end
end
