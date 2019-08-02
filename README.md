# MdnsLite

[![CircleCI](https://circleci.com/gh/pcmarks/mdns_lite.svg?style=svg)](https://circleci.com/gh/pcmarks/mdns_lite)

MdnsLite is a simple, limited, no frills implementation of an
[mDNS](https://en.wikipedia.org/wiki/Multicast_DNS) (multicast Domain Name System)
server. It operates like a DNS server, the difference being that it uses multicast
instead of unicast and is meant to be the DNS server for the _.local_ domain.
This module is a GenServer that can  manages several GenServers - one for each
network interface.

It recognizes the following [query types](https://en.wikipedia.org/wiki/List_of_DNS_record_types):

* A - Find the IPv4 address of a hostname.
* PTR - Given an IPv4 address, find its hostname.
* SRV - Service Locator

There are at least a couple of other Elixir/Erlang implementations of mDNS servers:

1. [Rosetta Home mdns](https://github.com/rosetta-home/mdns) (Elixir)
2. [Shortishly mdns](https://github.com/shortishly/mdns) (Erlang)

These implementations provided valuable guidance in the building of MdnsLite.

## Configuration

Note that listing the service doesn't guarantee the existence of that service.

```elixir
config :mdns_lite,
  # Use these values to construct the DNS resource record responses
  # to a DNS query.
  mdns_config: %{
    host: :hostname,
    ttl: 3600
  },
  services: [
    # service type: _http._tcp.local - used in match
    %{
      type: "_http._tcp",
      name: "Web Server",
      protocol: "http",
      transport: "tcp",
      port: 80,
      weight: 0,
      priority: 0
    },
    # service_type: _ssh._tcp.local - used in match
    %{
      type: "_ssh._tcp",
      name: "Secure Socket",
      protocol: "ssh",
      transport: "tcp",
      port: 22,
      weight: 0,
      priority: 0
    }
  ]
```

The `mdns_config` section is where you specify values that will be used in the
construction of mDNS responses. `host` can be `:hostname` in which case the value will be
replaced with the value of `:inet.gethostname()`, otherwise you can provide a
string value.

The `services` section lists details of the services that a host can supply,
such as providing an HTTP server.

A detailed
description of the various DNS/mDNS record types and their fields can be found
at [zytrax.com/books/dns](http://www.zytrax.com/books/dns).

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

## Usage

`MdnsLite` is started as a linked process. Subsequently, it is used to start an mDNS
server for a given network interface. It is these servers that support mDNS queries coming via
that network interface. Each server is started by
executing `MdnsLite.start_mdns_server("eth0")`, for example. To stop responding to
mDNS queries for a particular network, execute `MdnsLite.stop_mdns_server("eth0")`.

If desired, the MdnsLite module can be bypassed and the mDNS servers started
directly. It is then the user's responsibility for maintaining pointers to
the server(s). To find out what network interfaces are available, execute `:inet.getiflist`.

When MdnsLite is running, it can be tested using the linux `dig` utility:

```sh
dig @224.0.0.251 -p 5353 -t A petes-pt.local => 192.168.0.102

dig @224.0.0.251 -p 5353 -x 192.168.0.102 => petes-pt.local ``

dig @224.0.0.251 -p 5353 -t SRV _http._tcp.local => Depends on the service(s) available
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/mdns_lite](https://hexdocs.pm/mdns_lite).
