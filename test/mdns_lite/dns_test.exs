defmodule MdnsLite.DNSTest do
  use ExUnit.Case

  alias MdnsLite.DNS
  import MdnsLite.DNS

  test "encoding and decoding the Elgato packet" do
    encoded =
      <<0, 0, 132, 0, 0, 0, 0, 1, 0, 0, 0, 6, 4, 95, 101, 108, 103, 4, 95, 116, 99, 112, 5, 108,
        111, 99, 97, 108, 0, 0, 12, 0, 1, 0, 0, 17, 148, 0, 24, 21, 69, 108, 103, 97, 116, 111,
        32, 75, 101, 121, 32, 76, 105, 103, 104, 116, 32, 57, 57, 51, 66, 192, 12, 21, 101, 108,
        103, 97, 116, 111, 45, 107, 101, 121, 45, 108, 105, 103, 104, 116, 45, 57, 57, 51, 98,
        192, 22, 0, 1, 128, 1, 0, 0, 0, 120, 0, 4, 192, 168, 3, 39, 192, 63, 0, 28, 128, 1, 0, 0,
        0, 120, 0, 16, 254, 128, 0, 0, 0, 0, 0, 0, 62, 106, 157, 255, 254, 20, 213, 105, 192, 39,
        0, 33, 128, 1, 0, 0, 0, 120, 0, 8, 0, 0, 0, 0, 35, 163, 192, 63, 192, 39, 0, 16, 128, 1,
        0, 0, 17, 148, 0, 74, 9, 109, 102, 61, 69, 108, 103, 97, 116, 111, 5, 100, 116, 61, 53,
        51, 20, 105, 100, 61, 51, 67, 58, 54, 65, 58, 57, 68, 58, 49, 52, 58, 68, 53, 58, 54, 57,
        29, 109, 100, 61, 69, 108, 103, 97, 116, 111, 32, 75, 101, 121, 32, 76, 105, 103, 104,
        116, 32, 50, 48, 71, 65, 75, 57, 57, 48, 49, 6, 112, 118, 61, 49, 46, 48, 192, 63, 0, 47,
        128, 1, 0, 0, 0, 120, 0, 8, 192, 63, 0, 4, 64, 0, 0, 8, 192, 39, 0, 47, 128, 1, 0, 0, 0,
        120, 0, 9, 192, 39, 0, 5, 0, 0, 128, 0, 64>>

    decoded =
      dns_rec(
        header:
          dns_header(
            id: 0,
            qr: true,
            opcode: :query,
            aa: true,
            tc: false,
            rd: false,
            ra: false,
            pr: false,
            rcode: 0
          ),
        anlist: [
          dns_rr(
            domain: '_elg._tcp.local',
            type: :ptr,
            class: :in,
            ttl: 4500,
            data: 'Elgato Key Light 993B._elg._tcp.local'
          )
        ],
        arlist: [
          dns_rr(
            domain: 'elgato-key-light-993b.local',
            type: :a,
            class: :in,
            ttl: 120,
            data: {192, 168, 3, 39},
            func: true
          ),
          dns_rr(
            domain: 'elgato-key-light-993b.local',
            type: :aaaa,
            class: :in,
            ttl: 120,
            data: {65152, 0, 0, 0, 15978, 40447, 65044, 54633},
            func: true
          ),
          dns_rr(
            domain: 'Elgato Key Light 993B._elg._tcp.local',
            type: :srv,
            class: :in,
            ttl: 120,
            data: {0, 0, 9123, 'elgato-key-light-993b.local'},
            func: true
          ),
          dns_rr(
            domain: 'Elgato Key Light 993B._elg._tcp.local',
            type: :txt,
            class: :in,
            ttl: 4500,
            data: [
              'mf=Elgato',
              'dt=53',
              'id=3C:6A:9D:14:D5:69',
              'md=Elgato Key Light 20GAK9901',
              'pv=1.0'
            ],
            func: true
          ),
          dns_rr(
            domain: 'elgato-key-light-993b.local',
            type: 47,
            class: :in,
            ttl: 120,
            data: <<192, 63, 0, 4, 64, 0, 0, 8>>,
            func: true
          ),
          dns_rr(
            domain: 'Elgato Key Light 993B._elg._tcp.local',
            type: 47,
            class: :in,
            ttl: 120,
            data: <<192, 39, 0, 5, 0, 0, 128, 0, 64>>,
            func: true
          )
        ]
      )

    assert {:ok, decoded} == DNS.decode(encoded)
    assert encoded == DNS.encode(decoded)
  end

  test "encoding and decoding a query" do
    encoded =
      <<0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 11, 110, 101, 114, 118, 101, 115, 45, 49, 50, 51, 52,
        5, 108, 111, 99, 97, 108, 0, 0, 1, 0, 1>>

    decoded =
      dns_rec(
        header:
          dns_header(
            id: 0,
            qr: false,
            opcode: :query,
            aa: false,
            tc: false,
            rd: false,
            ra: false,
            pr: false,
            rcode: 0
          ),
        qdlist: [
          dns_query(class: :in, type: :a, domain: 'nerves-1234.local', unicast_response: false)
        ]
      )

    assert {:ok, decoded} == DNS.decode(encoded)
    assert encoded == DNS.encode(decoded)
  end

  test "encoding and decoding the unicast_response flag" do
    encoded =
      <<0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 11, 110, 101, 114, 118, 101, 115, 45, 49, 50, 51, 52,
        5, 108, 111, 99, 97, 108, 0, 0, 1, 128, 1>>

    decoded =
      dns_rec(
        header:
          dns_header(
            id: 0,
            qr: false,
            opcode: :query,
            aa: false,
            tc: false,
            rd: false,
            ra: false,
            pr: false,
            rcode: 0
          ),
        qdlist: [
          dns_query(class: :in, type: :a, domain: 'nerves-1234.local', unicast_response: true)
        ]
      )

    assert {:ok, decoded} == DNS.decode(encoded)
    assert encoded == DNS.encode(decoded)
  end

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
