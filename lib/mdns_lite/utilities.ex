defmodule MdnsLite.Utilities do
  @moduledoc false

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
end
