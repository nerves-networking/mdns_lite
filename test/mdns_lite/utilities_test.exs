defmodule MdnsLite.UtilitiesTest do
  use ExUnit.Case

  alias MdnsLite.Utilities

  doctest MdnsLite.Utilities

  defp test_ifaddrs() do
    [
      {'lo0',
       [
         flags: [:up, :loopback, :running, :multicast],
         addr: {127, 0, 0, 1},
         netmask: {255, 0, 0, 0},
         addr: {0, 0, 0, 0, 0, 0, 0, 1},
         netmask: {65535, 65535, 65535, 65535, 65535, 65535, 65535, 65535},
         addr: {65152, 0, 0, 0, 0, 0, 0, 1},
         netmask: {65535, 65535, 65535, 65535, 0, 0, 0, 0}
       ]},
      {'gif0', [flags: [:pointtopoint, :multicast]]},
      {'stf0', [flags: []]},
      {'XHC0', [flags: []]},
      {'XHC1', [flags: []]},
      {'XHC20', [flags: []]},
      {'en0',
       [
         flags: [:up, :broadcast, :running, :multicast],
         addr: {65152, 0, 0, 0, 3177, 34598, 19643, 57597},
         netmask: {65535, 65535, 65535, 65535, 0, 0, 0, 0},
         addr: {192, 168, 9, 213},
         netmask: {255, 255, 255, 0},
         broadaddr: {192, 168, 9, 255},
         hwaddr: [140, 133, 144, 54, 173, 41]
       ]},
      {'p2p0',
       [
         flags: [:up, :broadcast, :running, :multicast],
         hwaddr: [14, 133, 144, 54, 173, 41]
       ]},
      {'awdl0',
       [
         flags: [:up, :broadcast, :running, :multicast],
         addr: {65152, 0, 0, 0, 50389, 24319, 65082, 34455},
         netmask: {65535, 65535, 65535, 65535, 0, 0, 0, 0},
         hwaddr: [198, 213, 94, 58, 134, 151]
       ]},
      {'en1',
       [
         flags: [:up, :broadcast, :running, :multicast],
         hwaddr: [106, 0, 181, 2, 88, 1]
       ]},
      {'en2',
       [
         flags: [:up, :broadcast, :running, :multicast],
         hwaddr: [106, 0, 181, 2, 88, 0]
       ]},
      {'en3',
       [
         flags: [:up, :broadcast, :running, :multicast],
         hwaddr: [106, 0, 181, 2, 88, 5]
       ]},
      {'en4',
       [
         flags: [:up, :broadcast, :running, :multicast],
         hwaddr: [106, 0, 181, 2, 88, 4]
       ]},
      {'bridge0', [flags: [:broadcast, :multicast], hwaddr: [106, 0, 181, 2, 88, 1]]},
      {'utun0',
       [
         flags: [:up, :pointtopoint, :running, :multicast],
         addr: {65152, 0, 0, 0, 5736, 498, 36548, 10713},
         netmask: {65535, 65535, 65535, 65535, 0, 0, 0, 0},
         dstaddr: {20, 18, 22, 0}
       ]},
      {'utun1',
       [
         flags: [:up, :pointtopoint, :running, :multicast],
         addr: {65152, 0, 0, 0, 27257, 3319, 61087, 19401},
         netmask: {65535, 65535, 65535, 65535, 0, 0, 0, 0},
         dstaddr: {20, 18, 7, 0}
       ]},
      {'en5',
       [
         flags: [:up, :broadcast, :running, :multicast],
         addr: {65152, 0, 0, 0, 44766, 18687, 65024, 4386},
         netmask: {65535, 65535, 65535, 65535, 0, 0, 0, 0},
         hwaddr: [172, 222, 72, 0, 17, 34]
       ]}
    ]
  end

  test "ifaddrs_to_ip_list finds IP addresses" do
    assert Utilities.ifaddrs_to_ip_list(test_ifaddrs(), "en5") == [
             {65152, 0, 0, 0, 44766, 18687, 65024, 4386}
           ]

    assert Utilities.ifaddrs_to_ip_list(test_ifaddrs(), "en0") == [
             {65152, 0, 0, 0, 3177, 34598, 19643, 57597},
             {192, 168, 9, 213}
           ]

    assert Utilities.ifaddrs_to_ip_list(test_ifaddrs(), "bridge0") == []
    assert Utilities.ifaddrs_to_ip_list(test_ifaddrs(), "doesnt_exist0") == []
  end

  test "can tell IPv4 and IPv6 apart" do
    assert Utilities.ip_family({192, 168, 9, 213}) == :inet
    assert Utilities.ip_family({65152, 0, 0, 0, 3177, 34598, 19643, 57597}) == :inet6
  end
end
