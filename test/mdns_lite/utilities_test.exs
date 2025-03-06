# SPDX-FileCopyrightText: 2019 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule MdnsLite.UtilitiesTest do
  use ExUnit.Case

  alias MdnsLite.Utilities

  doctest MdnsLite.Utilities

  defp test_ifaddrs() do
    [
      {~c"lo0",
       [
         flags: [:up, :loopback, :running, :multicast],
         addr: {127, 0, 0, 1},
         netmask: {255, 0, 0, 0},
         addr: {0, 0, 0, 0, 0, 0, 0, 1},
         netmask: {65535, 65535, 65535, 65535, 65535, 65535, 65535, 65535},
         addr: {65152, 0, 0, 0, 0, 0, 0, 1},
         netmask: {65535, 65535, 65535, 65535, 0, 0, 0, 0}
       ]},
      {~c"gif0", [flags: [:pointtopoint, :multicast]]},
      {~c"stf0", [flags: []]},
      {~c"XHC0", [flags: []]},
      {~c"XHC1", [flags: []]},
      {~c"XHC20", [flags: []]},
      {~c"en0",
       [
         flags: [:up, :broadcast, :running, :multicast],
         addr: {65152, 0, 0, 0, 3177, 34598, 19643, 57597},
         netmask: {65535, 65535, 65535, 65535, 0, 0, 0, 0},
         addr: {192, 168, 9, 213},
         netmask: {255, 255, 255, 0},
         broadaddr: {192, 168, 9, 255},
         hwaddr: [140, 133, 144, 54, 173, 41]
       ]},
      {~c"p2p0",
       [
         flags: [:up, :broadcast, :running, :multicast],
         hwaddr: [14, 133, 144, 54, 173, 41]
       ]},
      {~c"awdl0",
       [
         flags: [:up, :broadcast, :running, :multicast],
         addr: {65152, 0, 0, 0, 50389, 24319, 65082, 34455},
         netmask: {65535, 65535, 65535, 65535, 0, 0, 0, 0},
         hwaddr: [198, 213, 94, 58, 134, 151]
       ]},
      {~c"en1",
       [
         flags: [:up, :broadcast, :running, :multicast],
         hwaddr: [106, 0, 181, 2, 88, 1]
       ]},
      {~c"en2",
       [
         flags: [:up, :broadcast, :running, :multicast],
         hwaddr: [106, 0, 181, 2, 88, 0]
       ]},
      {~c"en3",
       [
         flags: [:up, :broadcast, :running, :multicast],
         hwaddr: [106, 0, 181, 2, 88, 5]
       ]},
      {~c"en4",
       [
         flags: [:up, :broadcast, :running, :multicast],
         hwaddr: [106, 0, 181, 2, 88, 4]
       ]},
      {~c"bridge0", [flags: [:broadcast, :multicast], hwaddr: [106, 0, 181, 2, 88, 1]]},
      {~c"utun0",
       [
         flags: [:up, :pointtopoint, :running, :multicast],
         addr: {65152, 0, 0, 0, 5736, 498, 36548, 10713},
         netmask: {65535, 65535, 65535, 65535, 0, 0, 0, 0},
         dstaddr: {20, 18, 22, 0}
       ]},
      {~c"utun1",
       [
         flags: [:up, :pointtopoint, :running, :multicast],
         addr: {65152, 0, 0, 0, 27257, 3319, 61087, 19401},
         netmask: {65535, 65535, 65535, 65535, 0, 0, 0, 0},
         dstaddr: {20, 18, 7, 0}
       ]},
      {~c"en5",
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
