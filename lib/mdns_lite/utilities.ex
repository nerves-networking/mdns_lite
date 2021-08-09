defmodule MdnsLite.Utilities do
  @moduledoc false

  @sol_socket 0xFFFF
  @so_reuseport 0x0200
  @so_reuseaddr 0x0004

  @doc """
  Return a network interface's IP addresses

  * `ifaddrs` - the return value from `:inet.getifaddrs/0`
  """
  @spec ifaddrs_to_ip_list(
          [{ifname :: charlist(), ifopts :: :inet.getifaddrs_ifopts()}],
          ifname :: String.t()
        ) :: [:inet.ip_address()]
  def ifaddrs_to_ip_list(ifaddrs, ifname) do
    ifname_cl = to_charlist(ifname)

    case List.keyfind(ifaddrs, ifname_cl, 0) do
      nil ->
        []

      {^ifname_cl, params} ->
        Keyword.get_values(params, :addr)
    end
  end

  @doc """
  Return whether the IP address is IPv4 (:inet) or IPv6 (:inet6)
  """
  @spec ip_family(:inet.ip_address()) :: :inet | :inet6
  def ip_family({_, _, _, _}), do: :inet
  def ip_family({_, _, _, _, _, _, _, _}), do: :inet6

  @doc """
  Strip the flag bit off the class value

  This is required since OTP doesn't know about it and will return numbers rather than the
  the `:in` class.
  """
  def normalize_class(32769), do: :in
  def normalize_class(other), do: other

  @doc """
  Get the reuse port option for :gen_udp
  """
  @spec reuse_port_option() :: [{:raw, 65535, 4 | 512, <<_::32>>}]
  def reuse_port_option() do
    reuse_port(:os.type())
  end

  defp reuse_port({:unix, :linux}) do
    case :os.version() do
      {major, minor, _} when major > 3 or (major == 3 and minor >= 9) ->
        get_reuse_port()

      _before_3_9 ->
        get_reuse_address()
    end
  end

  defp reuse_port({:unix, os_name}) when os_name in [:darwin, :freebsd, :openbsd, :netbsd] do
    get_reuse_port()
  end

  defp reuse_port({:win32, _}) do
    get_reuse_address()
  end

  defp reuse_port(_), do: []

  defp get_reuse_port(), do: [{:raw, @sol_socket, @so_reuseport, <<1::native-32>>}]

  defp get_reuse_address(), do: [{:raw, @sol_socket, @so_reuseaddr, <<1::native-32>>}]
end
