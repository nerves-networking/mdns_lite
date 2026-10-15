# SPDX-FileCopyrightText: 2026 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule MdnsLite.PacketOriginTest do
  use ExUnit.Case, async: true

  alias MdnsLite.PacketOrigin

  @ipv4 {192, 168, 1, 10}
  @ipv4_mask {255, 255, 255, 0}
  @ipv6 {0x2001, 0xDB8, 1, 0, 0, 0, 0, 10}
  @ipv6_mask {0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0, 0, 0, 0}
  @ipv4_addresses [{@ipv4, @ipv4_mask}]
  @ipv6_addresses [{@ipv6, @ipv6_mask}]

  test "accepts same-subnet IPv4 unicast" do
    message = packet(:inet, {192, 168, 1, 20}, @ipv4)
    assert PacketOrigin.local?(message, :inet, 1, @ipv4_addresses)
  end

  test "rejects off-subnet IPv4 unicast" do
    message = packet(:inet, {203, 0, 113, 20}, @ipv4)
    refute PacketOrigin.local?(message, :inet, 1, @ipv4_addresses)
  end

  test "accepts IPv4 multicast from a different logical subnet on the same link" do
    message = packet(:inet, {203, 0, 113, 20}, {224, 0, 0, 251})
    assert PacketOrigin.local?(message, :inet, 1, @ipv4_addresses)
  end

  test "accepts any configured subnet, using its actual mask" do
    message = packet(:inet, {10, 20, 31, 40}, @ipv4)
    addresses = @ipv4_addresses ++ [{{10, 20, 0, 1}, {255, 255, 0, 0}}]
    assert PacketOrigin.local?(message, :inet, 1, addresses)
  end

  test "mask changes affect the origin policy immediately" do
    message = packet(:inet, {192, 168, 0, 20}, @ipv4)
    assert PacketOrigin.local?(message, :inet, 1, [{@ipv4, {255, 255, 254, 0}}])
    refute PacketOrigin.local?(message, :inet, 1, @ipv4_addresses)
  end

  test "loopback addresses are local only to the loopback subnet" do
    message = packet(:inet, {127, 0, 0, 2}, {127, 0, 0, 1})
    assert PacketOrigin.local?(message, :inet, 1, [{{127, 0, 0, 1}, {255, 0, 0, 0}}])
    refute PacketOrigin.local?(message, :inet, 1, @ipv4_addresses)
  end

  test "accepts IPv6 unicast on a configured local prefix" do
    source = {0x2001, 0xDB8, 1, 0, 0, 0, 0, 20}
    assert PacketOrigin.local?(packet(:inet6, source, @ipv6), :inet6, 1, @ipv6_addresses)
  end

  test "rejects IPv6 unicast outside the configured local prefixes" do
    source = {0x2001, 0xDB8, 2, 0, 0, 0, 0, 20}
    refute PacketOrigin.local?(packet(:inet6, source, @ipv6), :inet6, 1, @ipv6_addresses)
  end

  test "accepts IPv6 link-local unicast" do
    source = {0xFE80, 0, 0, 0, 0, 0, 0, 20}
    destination = {0xFE80, 0, 0, 0, 0, 0, 0, 10}
    addresses = [{destination, @ipv6_mask}]
    assert PacketOrigin.local?(packet(:inet6, source, destination), :inet6, 1, addresses)
  end

  test "accepts IPv6 multicast independently of the source prefix" do
    source = {0x2001, 0xDB8, 2, 0, 0, 0, 0, 20}
    destination = {0xFF02, 0, 0, 0, 0, 0, 0, 0xFB}
    assert PacketOrigin.local?(packet(:inet6, source, destination), :inet6, 1, @ipv6_addresses)
  end

  for {family, source, destination, addresses} <- [
        {:inet, {192, 168, 1, 20}, {224, 0, 0, 251}, @ipv4_addresses},
        {:inet6, @ipv6, {0xFF02, 0, 0, 0, 0, 0, 0, 0xFB}, @ipv6_addresses}
      ] do
    test "#{family} rejects packets received on another interface" do
      message =
        packet(unquote(family), unquote(Macro.escape(source)), unquote(Macro.escape(destination)))

      refute PacketOrigin.local?(message, unquote(family), 2, unquote(Macro.escape(addresses)))
    end

    test "#{family} rejects packets when the interface has no active addresses" do
      message =
        packet(unquote(family), unquote(Macro.escape(source)), unquote(Macro.escape(destination)))

      refute PacketOrigin.local?(message, unquote(family), 1, [])
    end
  end

  test "rejects missing and unrecognized metadata" do
    message = packet(:inet, {192, 168, 1, 20}, @ipv4)
    refute PacketOrigin.local?(%{message | ctrl: []}, :inet, 1, @ipv4_addresses)

    refute PacketOrigin.local?(
             %{message | ctrl: [%{level: :ip, type: :ttl}]},
             :inet,
             1,
             @ipv4_addresses
           )

    refute PacketOrigin.local?(Map.delete(message, :ctrl), :inet, 1, @ipv4_addresses)
  end

  test "rejects an unspecified interface index" do
    message = packet(:inet, {192, 168, 1, 20}, @ipv4, 0)
    refute PacketOrigin.local?(message, :inet, 0, @ipv4_addresses)
  end

  test "rejects a source address or control message with the wrong family" do
    message = packet(:inet, {192, 168, 1, 20}, @ipv4)
    refute PacketOrigin.local?(message, :inet6, 1, @ipv6_addresses)
    [info] = message.ctrl

    refute PacketOrigin.local?(
             %{message | ctrl: [%{info | level: :ipv6}]},
             :inet,
             1,
             @ipv4_addresses
           )
  end

  for flag <- [:trunc, :ctrunc] do
    test "rejects packets flagged #{flag}" do
      message = %{packet(:inet, {192, 168, 1, 20}, @ipv4) | flags: [unquote(flag)]}
      refute PacketOrigin.local?(message, :inet, 1, @ipv4_addresses)
    end
  end

  if :os.type() == {:unix, :darwin} do
    test "decodes native Darwin IPv6 packet information" do
      message = packet(:inet6, @ipv6, @ipv6)
      address = for part <- Tuple.to_list(@ipv6), into: <<>>, do: <<part::16>>
      info = %{level: :ipv6, type: 46, data: address <> <<1::native-32>>}
      assert PacketOrigin.local?(%{message | ctrl: [info]}, :inet6, 1, @ipv6_addresses)
      refute PacketOrigin.local?(%{message | ctrl: [info]}, :inet6, 2, @ipv6_addresses)

      refute PacketOrigin.local?(
               %{message | ctrl: [%{info | data: <<0>>}]},
               :inet6,
               1,
               @ipv6_addresses
             )
    end
  end

  defp packet(family, source, destination, index \\ 1) do
    %{
      addr: %{family: family, addr: source, port: 5353},
      flags: [],
      ctrl: [
        %{
          level: if(family == :inet, do: :ip, else: :ipv6),
          type: :pktinfo,
          value: %{addr: destination, ifindex: index}
        }
      ],
      iov: []
    }
  end
end
