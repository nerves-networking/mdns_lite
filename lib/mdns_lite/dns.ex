defmodule MdnsLite.DNS do
  import Record, only: [defrecord: 2]

  defrecord :dns_rec, Record.extract(:dns_rec, from_lib: "kernel/src/inet_dns.hrl")
  defrecord :dns_header, Record.extract(:dns_header, from_lib: "kernel/src/inet_dns.hrl")
  defrecord :dns_query, Record.extract(:dns_query, from_lib: "kernel/src/inet_dns.hrl")
  defrecord :dns_rr, Record.extract(:dns_rr, from_lib: "kernel/src/inet_dns.hrl")

  @type dns_query :: record(:dns_query, [])
  @type dns_rr :: record(:dns_rr, [])
end
