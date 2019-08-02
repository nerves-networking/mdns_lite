defmodule MdnsLite.QueryTest do
  use ExUnit.Case

  alias MdnsLite.Query

  doctest MdnsLite.Query

  defp test_state() do
    %MdnsLite.Responder.State{
      dot_local_name: 'nerves-21a5.local',
      ifname: "eth0",
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
      ttl: 3600,
      udp: nil
    }
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
        ttl: 3600,
        type: :a
      }
    ]

    assert Query.handle(query, test_state()) == result
  end

  test "ignores A request for someone else" do
    query = %DNS.Query{class: :in, domain: 'someone-else.local', type: :a}

    assert Query.handle(query, test_state()) == []
  end
end
