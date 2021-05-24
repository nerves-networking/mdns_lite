defmodule MdnsLite.QueryTest do
  use ExUnit.Case

  alias MdnsLite.Query
  import Record, only: [defrecord: 2]

  defrecord :dns_query, Record.extract(:dns_query, from_lib: "kernel/src/inet_dns.hrl")
  defrecord :dns_rr, Record.extract(:dns_rr, from_lib: "kernel/src/inet_dns.hrl")

  doctest MdnsLite.Query

  defp test_state() do
    %MdnsLite.Responder.State{
      dot_local_name: 'nerves-21a5.local',
      dot_alias_name: nil,
      instance_name: "nerves-21a5",
      ip: {192, 168, 9, 57},
      services: [
        %{
          name: "Web Server",
          txt_payload: ["key=value"],
          port: 80,
          priority: 0,
          protocol: "http",
          transport: "tcp",
          type: "_http._tcp",
          weight: 0
        },
        %{
          name: "Secure Socket",
          txt_payload: [""],
          port: 22,
          priority: 0,
          protocol: "ssh",
          transport: "tcp",
          type: "_ssh._tcp",
          weight: 0
        }
      ],
      ttl: 120,
      udp: nil
    }
  end

  defp test_alias_state() do
    test_state = test_state()
    %MdnsLite.Responder.State{test_state | dot_alias_name: 'nerves.local'}
  end

  test "responds to an A request" do
    query = dns_query(domain: 'nerves-21a5.local', type: :a, class: :in)

    result = [
      dns_rr(domain: 'nerves-21a5.local', type: :a, class: :in, ttl: 120, data: {192, 168, 9, 57})
    ]

    assert Query.handle(query, test_state()) == result
  end

  test "responds to an A request for the alias" do
    query = dns_query(domain: 'nerves.local', type: :a, class: :in)

    result = [
      dns_rr(domain: 'nerves.local', type: :a, class: :in, ttl: 120, data: {192, 168, 9, 57})
    ]

    assert Query.handle(query, test_alias_state()) == result
  end

  test "responds to a unicast A request" do
    query = dns_query(domain: 'nerves-21a5.local', type: :a, class: 32769)

    result = [
      dns_rr(domain: 'nerves-21a5.local', type: :a, class: :in, ttl: 120, data: {192, 168, 9, 57})
    ]

    assert Query.handle(query, test_state()) == result
  end

  test "ignores A request for someone else" do
    query = dns_query(domain: 'someone-else.local', type: :a, class: 32769)

    assert Query.handle(query, test_state()) == []
  end

  test "responds to a PTR request with a reverse lookup domain" do
    query = dns_query(domain: '57.9.168.192', type: :ptr, class: :in)

    result = [
      dns_rr(
        domain: '57.9.168.192.in-addr.arpa.',
        type: :ptr,
        class: :in,
        ttl: 120,
        data: test_state().dot_local_name
      )
    ]

    assert Query.handle(query, test_state()) == result
  end

  test "responds to a PTR request with a specific domain" do
    test_domain = '_http._tcp.local'
    query = dns_query(domain: test_domain, type: :ptr, class: :in)

    result = [
      dns_rr(
        domain: test_domain,
        type: :ptr,
        class: :in,
        ttl: 120,
        data: 'Web Server._http._tcp.local'
      ),
      dns_rr(
        domain: 'Web Server._http._tcp.local',
        type: :txt,
        class: :in,
        ttl: 120,
        data: ["key=value"]
      ),
      dns_rr(
        domain: 'Web Server._http._tcp.local',
        type: :srv,
        class: :in,
        ttl: 120,
        data: {0, 0, 80, 'nerves-21a5.local.'}
      ),
      dns_rr(domain: 'nerves-21a5.local', type: :a, class: :in, ttl: 120, data: {192, 168, 9, 57})
    ]

    assert Query.handle(query, test_state()) == result
  end

  test "responds to a PTR request with domain \'_services._dns-sd._udp.local\'" do
    test_domain = '_services._dns-sd._udp.local'
    query = dns_query(domain: test_domain, type: :ptr, class: :in)

    result =
      test_state().services
      |> Enum.reverse()
      |> Enum.map(fn service ->
        dns_rr(
          domain: test_domain,
          type: :ptr,
          class: :in,
          ttl: test_state().ttl,
          data: to_charlist(service.type <> ".local")
        )
      end)

    assert Query.handle(query, test_state()) == result
  end

  test "responds to an SRV request for a known service" do
    known_service = "nerves-21a5.local._http._tcp.local"
    query = dns_query(domain: to_charlist(known_service), type: :srv, class: :in)

    result =
      test_state().services
      |> Enum.flat_map(fn service ->
        local_service = service.type <> ".local"

        if local_service == known_service do
          target = test_state().dot_local_name ++ '.'
          data = {service.priority, service.weight, service.port, target}

          [
            dns_rr(
              domain: to_charlist(known_service),
              type: :srv,
              class: :in,
              ttl: 120,
              data: data
            )
          ]
        else
          []
        end
      end)

    assert Query.handle(query, test_state()) == result
  end

  test "ignore SRV request without the host (instance) name" do
    service_only = "_http._tcp.local"
    query = dns_query(domain: to_charlist(service_only), type: :srv, class: :in)

    assert Query.handle(query, test_state()) == []
  end
end
