defmodule MdnsLite.Table.BuilderTest do
  use ExUnit.Case

  import MdnsLite.DNS
  alias MdnsLite.Options
  alias MdnsLite.Table.Builder

  doctest MdnsLite.Table.Builder

  test "Adds A and AAAA records" do
    config = %Options{} |> Options.add_hosts(["nerves-1234"])
    table = Builder.from_options(config)

    assert dns_rr(
             class: :in,
             type: :a,
             ttl: 120,
             domain: 'nerves-1234.local',
             data: :ipv4_address
           ) in table

    assert dns_rr(
             class: :in,
             type: :aaaa,
             ttl: 120,
             domain: 'nerves-1234.local',
             data: :ipv6_address
           ) in table
  end

  test "Adds PTR records" do
    config = %Options{} |> Options.add_hosts(["nerves-1234"])
    table = Builder.from_options(config)

    assert dns_rr(
             class: :in,
             type: :ptr,
             ttl: 120,
             domain: :ipv4_arpa_address,
             data: 'nerves-1234.local'
           ) in table

    assert dns_rr(
             class: :in,
             type: :ptr,
             ttl: 120,
             domain: :ipv6_arpa_address,
             data: 'nerves-1234.local'
           ) in table
  end
end
