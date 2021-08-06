defmodule MdnsLite.DNS do
  @moduledoc """
  Bring Erlang's DNS record definitions into Elixir
  """
  import Record, only: [defrecord: 2]

  @inet_dns "kernel/src/inet_dns.hrl"

  defrecord :dns_rec, Record.extract(:dns_rec, from_lib: @inet_dns)
  defrecord :dns_header, Record.extract(:dns_header, from_lib: @inet_dns)
  defrecord :dns_query, Record.extract(:dns_query, from_lib: @inet_dns)
  defrecord :dns_rr, Record.extract(:dns_rr, from_lib: @inet_dns)

  @type dns_query :: record(:dns_query, [])
  @type dns_rr :: record(:dns_rr, [])
end
