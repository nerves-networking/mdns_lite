# SPDX-FileCopyrightText: 2026 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule MdnsLite.PacketOrigin do
  @moduledoc false

  import Bitwise

  @mdns_ipv4 {224, 0, 0, 251}
  @mdns_ipv6 {0xFF02, 0, 0, 0, 0, 0, 0, 0xFB}
  @darwin_ipv6_recvpktinfo 61
  @darwin_ipv6_pktinfo 46

  @type addresses() :: [{:inet.ip_address(), :inet.ip_address()}]

  @spec enable(:socket.socket(), :inet | :inet6) :: :ok | {:error, term()}
  def enable(socket, :inet), do: :socket.setopt(socket, :ip, :pktinfo, true)

  def enable(socket, :inet6) do
    if :socket.is_supported(:options, :ipv6, :recvpktinfo) do
      :socket.setopt(socket, :ipv6, :recvpktinfo, true)
    else
      case :os.type() do
        {:unix, :darwin} ->
          :socket.setopt_native(
            socket,
            {:ipv6, @darwin_ipv6_recvpktinfo},
            <<1::native-signed-32>>
          )

        _ ->
          {:error, :enotsup}
      end
    end
  end

  @spec local?(:socket.msg_recv(), :inet | :inet6, pos_integer(), addresses()) :: boolean()
  def local?(
        %{addr: %{family: family, addr: source}, ctrl: ctrl, flags: flags},
        family,
        index,
        addresses
      )
      when index > 0 do
    not (:trunc in flags or :ctrunc in flags) and
      Enum.any?(ctrl, &local_info?(&1, source, family, index, addresses))
  end

  def local?(_message, _family, _index, _addresses), do: false

  defp local_info?(info, source, family, index, addresses) do
    case packet_info(info, family) do
      {destination, ^index} ->
        addresses != [] and
          (multicast?(destination, family) or Enum.any?(addresses, &same_subnet?(source, &1)))

      _ ->
        false
    end
  end

  defp packet_info(%{level: :ip, type: :pktinfo, value: %{addr: addr, ifindex: index}}, :inet),
    do: {addr, index}

  defp packet_info(%{level: :ipv6, type: :pktinfo, value: %{addr: addr, ifindex: index}}, :inet6),
    do: {addr, index}

  defp packet_info(
         %{
           level: :ipv6,
           type: @darwin_ipv6_pktinfo,
           data: <<addr::binary-size(16), index::native-32>>
         },
         :inet6
       ) do
    # OTP may expose Darwin's struct in6_pktinfo without decoding it.
    case :os.type() do
      {:unix, :darwin} ->
        {List.to_tuple(for <<part::16 <- addr>>, do: part), index}

      _ ->
        nil
    end
  end

  defp packet_info(_info, _family), do: nil

  defp multicast?(@mdns_ipv4, :inet), do: true
  defp multicast?(@mdns_ipv6, :inet6), do: true
  defp multicast?(_address, _family), do: false

  defp same_subnet?(source, {address, mask})
       when tuple_size(source) == tuple_size(address) and
              tuple_size(address) == tuple_size(mask) do
    source
    |> Tuple.to_list()
    |> Enum.zip(Enum.zip(Tuple.to_list(address), Tuple.to_list(mask)))
    |> Enum.all?(fn {s, {a, m}} -> (s &&& m) == (a &&& m) end)
  end

  defp same_subnet?(_source, _address), do: false
end
