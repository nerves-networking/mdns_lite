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
  @type dns_rec :: record(:dns_rec, [])

  @spec pretty(dns_rr()) :: String.t()
  def pretty(dns_rr(domain: domain, type: :a, class: :in, ttl: ttl, data: data)) do
    "#{domain}: type A, class IN, ttl #{ttl}, addr #{ntoa(data)}"
  end

  def pretty(dns_rr(domain: domain, type: :aaaa, class: :in, ttl: ttl, data: data)) do
    "#{domain}: type AAAA, class IN, ttl #{ttl}, addr #{ntoa(data)}"
  end

  def pretty(dns_rr(domain: domain, type: :ptr, class: :in, ttl: ttl, data: data)) do
    "#{ptr_domain(domain)}: type PTR, class IN, ttl #{ttl}, #{data}"
  end

  def pretty(dns_rr(domain: domain, type: :txt, class: :in, ttl: ttl, data: data)) do
    "#{domain}: type TXT, class IN, ttl #{ttl}, #{Enum.join(data, ", ")}"
  end

  def pretty(
        dns_rr(
          domain: domain,
          type: :srv,
          class: :in,
          ttl: ttl,
          data: {priority, weight, port, target}
        )
      ) do
    "#{domain}: type SRV, class IN, ttl #{ttl}, priority #{priority}, weight #{weight}, port #{port}, #{target}"
  end

  def pretty(dns_rr(domain: domain, type: type, class: class, ttl: ttl)) do
    "#{domain}: type #{type}, class #{class}, ttl #{ttl}"
  end

  defp ntoa(:ipv4_address), do: "<interface_ipv4>"
  defp ntoa(:ipv6_address), do: "<interface_ipv6>"
  defp ntoa(addr) when is_tuple(addr), do: :inet.ntoa(addr)
  defp ntoa(<<a, b, c, d>>), do: :inet.ntoa({a, b, c, d})

  defp ntoa(<<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>),
    do: :inet.ntoa({a, b, c, d, e, f, g, h})

  defp ptr_domain(:ipv4_arpa_address), do: "<interface_ipv4>.in-addr.arpa"
  defp ptr_domain(:ipv6_arpa_address), do: "<interface_ipv6>.ip6.arpa"
  defp ptr_domain(other), do: other
end
