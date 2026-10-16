# SPDX-FileCopyrightText: 2026 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule MdnsLite.DNSBridgeTest do
  use ExUnit.Case, async: false

  import MdnsLite.DNS

  alias MdnsLite.Cache
  alias MdnsLite.DNSBridge
  alias MdnsLite.Options
  alias MdnsLite.Responder

  setup do
    records = [
      dns_rr(
        domain: ~c"bridge-cache-test.local",
        type: :a,
        class: :in,
        ttl: 120,
        data: {192, 0, 2, 123},
        func: true
      ),
      dns_rr(
        domain: ~c"bridge-cache-test._http._tcp.local",
        type: :srv,
        class: :in,
        ttl: 120,
        data: {0, 0, 80, ~c"bridge-cache-test.local."},
        func: true
      )
    ]

    responder = start_supervised!({Responder, {"dns_bridge_test", {127, 0, 0, 1}}})
    cache = Cache.insert_many(Cache.new(), System.monotonic_time(:second), records)
    :sys.replace_state(responder, &%{&1 | cache: cache})

    bridge =
      start_supervised!(
        {DNSBridge,
         %Options{
           dns_bridge_enabled: true,
           dns_bridge_ip: {127, 0, 0, 1},
           dns_bridge_port: 0
         }}
      )

    {:ok, port} = :inet.port(:sys.get_state(bridge).udp)
    %{resolver_options: [nameservers: [{{127, 0, 0, 1}, port}]], responder: responder}
  end

  test "Erlang resolves cached addresses with mDNS cache-flush flags", context do
    assert {:ok, {:hostent, _, _, :inet, 4, [{192, 0, 2, 123}]}} =
             :inet_res.gethostbyname(
               ~c"bridge-cache-test.local",
               :inet,
               context.resolver_options,
               1000
             )

    assert Enum.all?(Responder.get_cache(context.responder).records, &dns_rr(&1, :func))
  end

  test "clears cache-flush flags on answer and additional records", context do
    assert {:ok, response} =
             :inet_res.resolve(
               ~c"bridge-cache-test._http._tcp.local",
               :in,
               :srv,
               context.resolver_options,
               1000
             )

    assert [dns_rr(type: :srv, class: :in, func: false)] = dns_rec(response, :anlist)

    assert [dns_rr(type: :a, class: :in, data: {192, 0, 2, 123}, func: false)] =
             dns_rec(response, :arlist)

    assert Enum.all?(Responder.get_cache(context.responder).records, &dns_rr(&1, :func))
  end
end
