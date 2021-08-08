defmodule MdnsLite.Info do
  alias MdnsLite.{TableServer, Responder}

  @doc """
  Dump the records that mDNSLite advertises
  """
  @spec dump_records() :: :ok
  def dump_records() do
    TableServer.get_records()
    |> format_rr([], "\n")
    |> IO.puts()
  end

  @doc """
  Dump the contents of the responder mDNS caches
  """
  @spec dump_caches() :: :ok
  def dump_caches() do
    Responder.get_all_caches()
    |> Enum.map(fn {ip, cache} ->
      [
        "Responder: ",
        :inet.ntoa(ip),
        "\n",
        format_rr(cache.records, "  ", "\n")
      ]
    end)
    |> IO.puts()
  end

  defp format_rr(rr, prefix, postfix) do
    rr
    |> Enum.sort()
    |> Enum.map(fn rec -> [prefix, MdnsLite.DNS.pretty(rec), postfix] end)
  end
end
