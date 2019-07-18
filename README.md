# MdnsLite

MdnsLite is a simple, limited, no frills implementation of an
[mDNS](https://en.wikipedia.org/wiki/Multicast_DNS) (multicast Domain Name System)
server.

It can handle the following [query types](https://en.wikipedia.org/wiki/List_of_DNS_record_types):
* A - Find the IPv4 address of a hostname.
* PTR - Given an IPv4 address, find its hostname.
* SRV - Service Locator

## Configuration
MDNSLite can be configured to recognize all or a subset of the
mDNS query types listed above. Note that
listing the service doesn't guarantee the existence of that service.
```Elixir
config :mdns_lite,
  mdns_ip: {224, 0, 0, 251},
  mdns_port: 5353,
  # Use these values to construct the DNS resource record responses
  # to a DNS query.
  mdns_config: %{
    host: :hostname,  # if :hostname, retrieve the hostname via :inet.gethostname()
    domain: "local",
    ttl: 3600,
    query_types: [
      # IP address lookup,
      :a,
      # Reverse IP lookup
      :ptr,
      # Services - see below
      :srv
    ]},
    services: [
      %{type: "_http._tcp", name: "Web Server",
        protocol: "http", transport: "tcp", port: 80, weight: 0, priority: 0},
      %{type: "_ssh._tcp", name: "Secure Socket",
        protocol: "ssh", transport: "tcp", port: 22, weight: 0, priority: 0
      }
    ]
  }
```
While MdnsLite is running, it can be tested using the linux utility `dig`:

  ``` dig @224.0.0.251 -p 5353 -t A petes-pt.local => 192.168.0.102 ```

  ``` dig @224.0.0.251 -p 5353 -x 192.168.0.102 => petes-pt.local ```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `mdns_lite` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mdns_lite, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/mdns_lite](https://hexdocs.pm/mdns_lite).
