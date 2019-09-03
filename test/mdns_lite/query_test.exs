defmodule MdnsLite.QueryTest do
  use ExUnit.Case

  alias MdnsLite.Query

  doctest MdnsLite.Query

  defp test_state() do
    %MdnsLite.Responder.State{
      dot_local_name: 'nerves-21a5.local',
      dot_alias_name: nil,
      ip: {192, 168, 9, 57},
      services: [
        %{
          name: "Web Server",
          port: 80,
          priority: 0,
          protocol: "http",
          transport: "tcp",
          type: "_http._tcp",
          weight: 0
        },
        %{
          name: "Secure Socket",
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
    query = %DNS.Query{class: :in, domain: 'nerves-21a5.local', type: :a}

    result = [
      %DNS.Resource{
        bm: [],
        class: :in,
        cnt: 0,
        data: {192, 168, 9, 57},
        domain: 'nerves-21a5.local',
        func: false,
        tm: :undefined,
        ttl: 120,
        type: :a
      }
    ]

    assert Query.handle(query, test_state()) == result
  end

  test "responds to an A request for the alias" do
    query = %DNS.Query{class: :in, domain: 'nerves.local', type: :a}

    result = [
      %DNS.Resource{
        bm: [],
        class: :in,
        cnt: 0,
        data: {192, 168, 9, 57},
        domain: 'nerves.local',
        func: false,
        tm: :undefined,
        ttl: 120,
        type: :a
      }
    ]

    assert Query.handle(query, test_alias_state()) == result
  end

  test "ignores A request for someone else" do
    query = %DNS.Query{class: :in, domain: 'someone-else.local', type: :a}

    assert Query.handle(query, test_state()) == []
  end

  test "responds to a PTR request" do
    query = %DNS.Query{class: :in, domain: '57.9.168.192', type: :ptr}

    result = [
      %DNS.Resource{
        bm: [],
        class: :in,
        cnt: 0,
        data: test_state().dot_local_name,
        domain: '57.9.168.192.in-addr.arpa.',
        func: false,
        tm: :undefined,
        ttl: 120,
        type: :ptr
      }
    ]

    assert Query.handle(query, test_state()) == result
  end

  test "responds to a PTR request with domain \'_services._dns-sd._udp.local\'" do
    test_domain = '_services._dns-sd._udp.local'
    query = %DNS.Query{class: :in, domain: test_domain, type: :ptr}

    result =
      test_state().services
      |> Enum.map(fn service ->
        %DNS.Resource{
          domain: test_domain,
          class: :in,
          type: :ptr,
          ttl: test_state().ttl,
          data: to_charlist(service.type <> ".local")
        }
      end)

    assert Query.handle(query, test_state()) == result
  end

  test "responds to an SRV request for a known service" do
    known_service = "nerves-21a5.local._http._tcp.local"
    query = %DNS.Query{class: :in, domain: to_charlist(known_service), type: :srv}

    result =
      test_state().services
      |> Enum.flat_map(fn service ->
        local_service = service.type <> ".local"

        if local_service == known_service do
          target = test_state().dot_local_name ++ '.'
          data = {service.priority, service.weight, service.port, target}

          [
            %DNS.Resource{
              class: :in,
              type: :srv,
              ttl: test_state().ttl,
              data: data
            }
          ]
        else
          []
        end
      end)

    assert Query.handle(query, test_state()) == result
  end

  test "ignore SRV request without the host (instance) name" do
    service_only = "_http._tcp.local"
    query = %DNS.Query{class: :in, domain: to_charlist(service_only), type: :srv}
    assert Query.handle(query, test_state()) == []
  end
end
