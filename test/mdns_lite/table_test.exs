defmodule MdnsLite.TableTest do
  use ExUnit.Case

  alias MdnsLite.{Options, Table}
  import MdnsLite.DNS

  doctest MdnsLite.Table

  defp test_config() do
    %Options{}
    |> Options.add_hosts(["nerves-21a5", "nerves"])
    |> Options.add_services([
      %{
        id: :http_service,
        txt_payload: ["key=value"],
        port: 80,
        priority: 0,
        protocol: "http",
        transport: "tcp",
        type: "_http._tcp",
        weight: 0
      },
      %{
        id: :ssh_service,
        txt_payload: [""],
        port: 22,
        priority: 0,
        protocol: "ssh",
        transport: "tcp",
        type: "_ssh._tcp",
        weight: 0
      }
    ])
  end

  def do_query(query, config \\ test_config()) do
    table = Table.Builder.from_options(config)
    if_info = %MdnsLite.IfInfo{ipv4_address: {192, 168, 9, 57}}
    answer_rr = Table.query(table, query, if_info)
    additional_rr = Table.additional_records(table, answer_rr, if_info)
    %{answer: answer_rr, additional: additional_rr}
  end

  test "responds to an A request" do
    query = dns_query(domain: 'nerves-21a5.local', type: :a, class: :in)

    result = %{
      answer: [
        dns_rr(
          domain: 'nerves-21a5.local',
          type: :a,
          class: :in,
          ttl: 120,
          data: {192, 168, 9, 57}
        )
      ],
      additional: []
    }

    assert do_query(query) == result
  end

  test "responds to an A request for the alias" do
    query = dns_query(domain: 'nerves.local', type: :a, class: :in)

    result = %{
      answer: [
        dns_rr(domain: 'nerves.local', type: :a, class: :in, ttl: 120, data: {192, 168, 9, 57})
      ],
      additional: []
    }

    assert do_query(query) == result
  end

  test "responds to a unicast A request" do
    query = dns_query(domain: 'nerves-21a5.local', type: :a, class: :in, unicast_response: true)

    result = %{
      answer: [
        dns_rr(
          domain: 'nerves-21a5.local',
          type: :a,
          class: :in,
          ttl: 120,
          data: {192, 168, 9, 57}
        )
      ],
      additional: []
    }

    assert do_query(query) == result
  end

  test "ignores A request for someone else" do
    query = dns_query(domain: 'someone-else.local', type: :a, class: :in, unicast_response: true)

    assert do_query(query) == %{answer: [], additional: []}
  end

  test "responds to a PTR request with a reverse lookup domain" do
    query = dns_query(domain: '57.9.168.192.in-addr.arpa.', type: :ptr, class: :in)

    result = %{
      answer: [
        dns_rr(
          domain: '57.9.168.192.in-addr.arpa.',
          type: :ptr,
          class: :in,
          ttl: 120,
          data: 'nerves-21a5.local'
        )
      ],
      additional: []
    }

    assert do_query(query) == result
  end

  test "responds to a PTR request with a specific domain" do
    test_domain = '_http._tcp.local'
    query = dns_query(domain: test_domain, type: :ptr, class: :in)

    result = %{
      answer: [
        dns_rr(
          domain: test_domain,
          type: :ptr,
          class: :in,
          ttl: 120,
          data: 'nerves-21a5._http._tcp.local'
        )
      ],
      additional: [
        dns_rr(
          domain: 'nerves-21a5._http._tcp.local',
          type: :srv,
          class: :in,
          ttl: 120,
          data: {0, 0, 80, 'nerves-21a5.local.'}
        ),
        dns_rr(
          domain: 'nerves-21a5._http._tcp.local',
          type: :txt,
          class: :in,
          ttl: 120,
          data: ["key=value"]
        ),
        dns_rr(
          domain: 'nerves-21a5.local',
          type: :a,
          class: :in,
          ttl: 120,
          data: {192, 168, 9, 57}
        )
      ]
    }

    assert do_query(query) == result
  end

  test "responds to a PTR request with a specific domain using host-level instance name" do
    test_domain = '_http._tcp.local'
    query = dns_query(domain: test_domain, type: :ptr, class: :in)

    result = %{
      answer: [
        dns_rr(
          domain: test_domain,
          type: :ptr,
          class: :in,
          ttl: 120,
          data: 'myidentifier._http._tcp.local'
        )
      ],
      additional: [
        dns_rr(
          domain: 'myidentifier._http._tcp.local',
          type: :srv,
          class: :in,
          ttl: 120,
          data: {0, 0, 80, 'nerves-21a5.local.'}
        ),
        dns_rr(
          domain: 'myidentifier._http._tcp.local',
          type: :txt,
          class: :in,
          ttl: 120,
          data: ["key=value"]
        ),
        dns_rr(
          domain: 'nerves-21a5.local',
          type: :a,
          class: :in,
          ttl: 120,
          data: {192, 168, 9, 57}
        )
      ]
    }

    config =
      %Options{}
      |> Options.add_hosts(["nerves-21a5", "nerves"])
      |> Options.set_instance_name("myidentifier")
      |> Options.add_service(%{
        id: :http_service,
        txt_payload: ["key=value"],
        port: 80,
        priority: 0,
        protocol: "http",
        transport: "tcp",
        type: "_http._tcp",
        weight: 0
      })

    assert do_query(query, config) == result
  end

  test "responds to a PTR request with a specific domain using service-level instance name" do
    test_domain = '_http._tcp.local'
    query = dns_query(domain: test_domain, type: :ptr, class: :in)

    result = %{
      answer: [
        dns_rr(
          domain: test_domain,
          type: :ptr,
          class: :in,
          ttl: 120,
          data: 'myidentifier._http._tcp.local'
        )
      ],
      additional: [
        dns_rr(
          domain: 'myidentifier._http._tcp.local',
          type: :srv,
          class: :in,
          ttl: 120,
          data: {0, 0, 80, 'nerves-21a5.local.'}
        ),
        dns_rr(
          domain: 'myidentifier._http._tcp.local',
          type: :txt,
          class: :in,
          ttl: 120,
          data: ["key=value"]
        ),
        dns_rr(
          domain: 'nerves-21a5.local',
          type: :a,
          class: :in,
          ttl: 120,
          data: {192, 168, 9, 57}
        )
      ]
    }

    config =
      %Options{}
      |> Options.add_hosts(["nerves-21a5", "nerves"])
      |> Options.add_service(%{
        id: :http_service,
        instance_name: "myidentifier",
        txt_payload: ["key=value"],
        port: 80,
        priority: 0,
        protocol: "http",
        transport: "tcp",
        type: "_http._tcp",
        weight: 0
      })

    assert do_query(query, config) == result
  end

  test "responds to a PTR request with domain \'_services._dns-sd._udp.local\'" do
    test_domain = '_services._dns-sd._udp.local'
    query = dns_query(domain: test_domain, type: :ptr, class: :in)

    result = %{
      answer: [
        dns_rr(
          domain: '_services._dns-sd._udp.local',
          type: :ptr,
          class: :in,
          ttl: 120,
          data: '_http._tcp.local'
        ),
        dns_rr(
          domain: '_services._dns-sd._udp.local',
          type: :ptr,
          class: :in,
          ttl: 120,
          data: '_ssh._tcp.local'
        )
      ],
      additional: []
    }

    assert do_query(query) == result
  end

  test "responds to an SRV request for a known service" do
    known_service = "nerves-21a5._http._tcp.local"
    query = dns_query(domain: to_charlist(known_service), type: :srv, class: :in)

    result = %{
      answer: [
        dns_rr(
          domain: 'nerves-21a5._http._tcp.local',
          type: :srv,
          class: :in,
          ttl: 120,
          data: {0, 0, 80, 'nerves-21a5.local.'}
        )
      ],
      additional: [
        {:dns_rr, 'nerves-21a5.local', :a, :in, 0, 120, {192, 168, 9, 57}, :undefined, [], false}
      ]
    }

    assert do_query(query) == result
  end

  test "responds to an SRV request for a known service with host-level instance name" do
    known_service = "myidentifier._http._tcp.local"
    query = dns_query(domain: to_charlist(known_service), type: :srv, class: :in)

    result = %{
      answer: [
        dns_rr(
          domain: 'myidentifier._http._tcp.local',
          type: :srv,
          class: :in,
          ttl: 120,
          data: {0, 0, 80, 'nerves-21a5.local.'}
        )
      ],
      additional: [
        {:dns_rr, 'nerves-21a5.local', :a, :in, 0, 120, {192, 168, 9, 57}, :undefined, [], false}
      ]
    }

    config =
      %Options{}
      |> Options.add_hosts(["nerves-21a5", "nerves"])
      |> Options.set_instance_name("myidentifier")
      |> Options.add_service(%{
        id: :http_service,
        txt_payload: ["key=value"],
        port: 80,
        priority: 0,
        protocol: "http",
        transport: "tcp",
        type: "_http._tcp",
        weight: 0
      })

    assert do_query(query, config) == result
  end

  test "responds to an SRV request for a known service with service-level instance name" do
    known_service = "myidentifier._http._tcp.local"
    query = dns_query(domain: to_charlist(known_service), type: :srv, class: :in)

    result = %{
      answer: [
        dns_rr(
          domain: 'myidentifier._http._tcp.local',
          type: :srv,
          class: :in,
          ttl: 120,
          data: {0, 0, 80, 'nerves-21a5.local.'}
        )
      ],
      additional: [
        {:dns_rr, 'nerves-21a5.local', :a, :in, 0, 120, {192, 168, 9, 57}, :undefined, [], false}
      ]
    }

    config =
      %Options{}
      |> Options.add_hosts(["nerves-21a5", "nerves"])
      |> Options.add_service(%{
        id: :http_service,
        instance_name: "myidentifier",
        txt_payload: ["key=value"],
        port: 80,
        priority: 0,
        protocol: "http",
        transport: "tcp",
        type: "_http._tcp",
        weight: 0
      })

    assert do_query(query, config) == result
  end

  test "ignore SRV request without the instance name" do
    service_only = "_http._tcp.local"
    query = dns_query(domain: to_charlist(service_only), type: :srv, class: :in)

    assert do_query(query) == %{answer: [], additional: []}
  end
end
