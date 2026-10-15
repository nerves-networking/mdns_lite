# SPDX-FileCopyrightText: 2019 Jon Carstens
# SPDX-FileCopyrightText: 2024 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule MdnsLite.ResponderTest do
  use ExUnit.Case, async: false

  import MdnsLite.DNS

  alias MdnsLite.Cache
  alias MdnsLite.DNS
  alias MdnsLite.PacketOrigin
  alias MdnsLite.Responder
  alias MdnsLite.TableServer

  test "stopping a nonexistent responder" do
    Responder.stop_server("no_exist", {1, 2, 3, 4})
  end

  for family <- TestUtilities.available_families(), response <- [true, false] do
    test "#{family} caches local #{if response, do: "response", else: "query"} records" do
      {state, sender, destination} = receive_state(unquote(family))
      message = records_message(unquote(response))
      new_state = deliver(state, sender, destination, message)
      assert Enum.sort(new_state.cache.records) == Enum.sort(message_records(message))
    end

    test "#{family} rejects wrong-interface #{if response, do: "response", else: "query"} records" do
      {state, sender, destination} = receive_state(unquote(family))
      state = %{state | ifindex: state.ifindex + 1}
      new_state = deliver(state, sender, destination, records_message(unquote(response)))
      assert new_state.cache == state.cache
    end
  end

  test "rejects packets when receive-side packet information is missing" do
    {state, sender, destination} = receive_state(:inet, false)
    new_state = deliver(state, sender, destination, records_message(true))
    assert new_state.cache == state.cache
  end

  test "answers local queries but does not answer queries from another interface" do
    {state, sender, destination} = receive_state(:inet)
    rr = Enum.find(TableServer.get_records(), &match?(dns_rr(type: :a), &1))

    message =
      dns_rec(
        header: dns_header(qr: false),
        qdlist: [
          dns_query(domain: dns_rr(rr, :domain), type: :a, class: :in, unicast_response: true)
        ]
      )

    new_state = deliver(state, sender, destination, message)
    assert {:ok, {_source, data}} = :socket.recvfrom(sender, [], 1000)
    assert {:ok, dns_rec(header: dns_header(qr: true), anlist: [_ | _])} = DNS.decode(data)

    deliver(%{new_state | ifindex: state.ifindex + 1}, sender, destination, message)
    assert {:error, :timeout} = :socket.recvfrom(sender, [], 20)
  end

  {:ok, interfaces} = :net.getifaddrs(:inet)

  @non_loopback_address Enum.find_value(interfaces, fn
                          %{flags: flags, addr: %{addr: address}} ->
                            if :up in flags and :loopback not in flags, do: address

                          _ ->
                            nil
                        end)

  if @non_loopback_address do
    for response <- [true, false] do
      test "rejects real off-subnet #{if response, do: "response", else: "query"} records" do
        {state, _sender, destination} = receive_state(:inet)
        {:ok, sender} = :socket.open(:inet, :dgram, :udp)
        on_exit(fn -> :socket.close(sender) end)
        :ok = :socket.bind(sender, %{family: :inet, addr: @non_loopback_address, port: 0})
        new_state = deliver(state, sender, destination, records_message(unquote(response)))
        assert new_state.cache == state.cache
      end
    end
  end

  defp receive_state(family, packet_info \\ true) do
    address = if family == :inet, do: {127, 0, 0, 1}, else: {0, 0, 0, 0, 0, 0, 0, 1}
    {:ok, interfaces} = :net.getifaddrs(family)
    %{name: name} = Enum.find(interfaces, &match?(%{addr: %{addr: ^address}}, &1))
    {:ok, index} = :net.if_name2index(name)
    {:ok, receiver} = :socket.open(family, :dgram, :udp)
    {:ok, sender} = :socket.open(family, :dgram, :udp)
    on_exit(fn -> :socket.close(receiver) end)
    on_exit(fn -> :socket.close(sender) end)
    if packet_info, do: :ok = PacketOrigin.enable(receiver, family)
    :ok = :socket.bind(receiver, %{family: family, addr: address, port: 0})
    {:ok, destination} = :socket.sockname(receiver)
    {:select, {:select_info, _tag, handle}} = :socket.recvmsg(receiver, 65535, 1024, [], :nowait)

    state = %{
      ifname: List.to_string(name),
      ip: address,
      family: family,
      ifindex: index,
      cache: Cache.new(),
      udp: receiver,
      select_handle: handle,
      skip_udp: false
    }

    {state, sender, destination}
  end

  defp deliver(state, sender, destination, message) do
    :ok = :socket.sendto(sender, DNS.encode(message), destination)
    event = {:"$socket", state.udp, :select, state.select_handle}
    assert_receive ^event, 1000
    {:noreply, new_state} = Responder.handle_info(event, state)
    new_state
  end

  defp records_message(response) do
    dns_rec(
      header: dns_header(qr: response),
      anlist: [
        dns_rr(
          domain: ~c"injected.local",
          type: :a,
          class: :in,
          ttl: 120,
          data: {203, 0, 113, 66}
        )
      ],
      arlist: [
        dns_rr(
          domain: ~c"additional.local",
          type: :a,
          class: :in,
          ttl: 120,
          data: {203, 0, 113, 67}
        )
      ]
    )
  end

  defp message_records(dns_rec(anlist: answer, arlist: additional)), do: answer ++ additional
end
