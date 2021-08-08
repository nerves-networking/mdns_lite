defmodule MdnsLite.DNSTest do
  use ExUnit.Case

  import MdnsLite.DNS

  describe "pretty/1 for rr" do
    test "a" do
      assert pretty(
               dns_rr(
                 class: :in,
                 type: :a,
                 ttl: 120,
                 domain: 'nerves-1234.local',
                 data: :ipv4_address
               )
             ) == "nerves-1234.local: type A, class IN, ttl 120, addr <interface_ipv4>"

      assert pretty(
               dns_rr(
                 class: :in,
                 type: :a,
                 ttl: 120,
                 domain: 'nerves-1234.local',
                 data: {1, 2, 3, 4}
               )
             ) == "nerves-1234.local: type A, class IN, ttl 120, addr 1.2.3.4"
    end

    test "aaaa" do
      assert pretty(
               dns_rr(
                 class: :in,
                 type: :aaaa,
                 ttl: 120,
                 domain: 'nerves-1234.local',
                 data: :ipv6_address
               )
             ) == "nerves-1234.local: type AAAA, class IN, ttl 120, addr <interface_ipv6>"

      assert pretty(
               dns_rr(
                 class: :in,
                 type: :aaaa,
                 ttl: 120,
                 domain: 'nerves-1234.local',
                 data: {65152, 0, 0, 0, 3297, 21943, 7498, 1443}
               )
             ) == "nerves-1234.local: type AAAA, class IN, ttl 120, addr fe80::ce1:55b7:1d4a:5a3"
    end

    test "ptr" do
      assert pretty(
               assert dns_rr(
                        class: :in,
                        type: :ptr,
                        ttl: 120,
                        domain: :ipv4_arpa_address,
                        data: 'nerves-1234.local'
                      )
             ) == "<interface_ipv4>.in-addr.arpa: type PTR, class IN, ttl 120, nerves-1234.local"
    end

    test "txt" do
      assert pretty(
               dns_rr(
                 domain: 'nerves-21a5._http._tcp.local',
                 type: :txt,
                 class: :in,
                 ttl: 120,
                 data: ["key1=1", "key2=2"]
               )
             ) == "nerves-21a5._http._tcp.local: type TXT, class IN, ttl 120, key1=1, key2=2"
    end

    test "srv" do
      assert pretty(
               dns_rr(
                 domain: 'nerves-21a5._http._tcp.local',
                 type: :srv,
                 class: :in,
                 ttl: 120,
                 data: {0, 0, 80, 'nerves-21a5.local.'}
               )
             ) ==
               "nerves-21a5._http._tcp.local: type SRV, class IN, ttl 120, priority 0, weight 0, port 80, nerves-21a5.local."
    end
  end
end
