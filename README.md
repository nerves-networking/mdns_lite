# MdnsLite

[![CircleCI](https://circleci.com/gh/pcmarks/mdns_lite.svg?style=svg)](https://circleci.com/gh/pcmarks/mdns_lite)

MdnsLite is a simple, limited, no frills implementation of an
[mDNS](https://en.wikipedia.org/wiki/Multicast_DNS) (multicast Domain Name System)
server. It operates like a DNS server, the difference being that it uses multicast
instead of unicast and is meant to be the DNS server for the _.local_ domain. MdnsLite
also provides for the advertising (discovery) of services offered by the host system.
Examples of services are an HTTP or an SSH server. Read about configuring
services in the Configuration section below.

MdnsLite employs a network interface monitor that can dynamically adjust to
network changes, e.g., assignment of a new IP address to a host. You can add your own Network Monitor;
a future release will allow the use of another implementation.

It recognizes the following [query types](https://en.wikipedia.org/wiki/List_of_DNS_record_types):

* A - Find the IPv4 address of a hostname.
* PTR - Given an IPv4 address, find its hostname - reverse lookup. If, however, it receives a request domain of
"_services._dns-sd._udp.local", MdnsLite will respond with a list of
every service available (and is specified in the configuration) on the host.
* SRV - Service Locator

If you want to know the details of the various DNS/mDNS record types and their fields,
a good source is
[zytrax.com/books/dns](http://www.zytrax.com/books/dns).

There are at least a couple of other Elixir/Erlang implementations of mDNS servers:

1. [Rosetta Home mdns](https://github.com/rosetta-home/mdns) (Elixir)
2. [Shortishly mdns](https://github.com/shortishly/mdns) (Erlang)

These implementations provided valuable guidance in the building of MdnsLite.

## Configuration

A typical configuration in the `config.exs` file looks
like:
```elixir
config :mdns_lite,
  # Use these values to construct the DNS resource record responses
  # to a DNS query.
  mdns_config: %{
    host: :hostname,
    ttl: 120
  },
  services: [
    # service type: _http._tcp.local - used in match
    %{
      name: "Web Server",
      protocol: "http",
      transport: "tcp",
      port: 80,
    },
    # service_type: _ssh._tcp.local - used in match
    %{
      name: "Secure Socket",
      protocol: "ssh",
      transport: "tcp",
      port: 22,
    }
  ]
```

The `mdns_config` section is where you specify values that will be used in the
construction of mDNS (DNS) responses. `host` can be `:hostname` in which case the value will be
replaced with the value of `:inet.gethostname()`, otherwise you can provide a
string value. `ttl` refers to a Time To Live value in seconds. [RFC 6762 - Multicast
DNS](https://tools.ietf.org/html/rfc6762) - recommends a default value of 120 seconds.

The `services` section lists the services that the host offers,
such as providing an HTTP server. You must supply the `protocol`, `transport` and
`port` values for each service.

MdnsLite uses a "network monitor", a module that listens for changes in a network.
Its purpose is to ensure that the network interfaces are up to date. The current
version of MdnsLite has an `InetMonitor` which periodically checks via `inet:getifaddrs()`
for changes in the network. A change could be the re-assignment of IP addresses.
## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `mdns_lite` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mdns_lite, "~> 0.2"}
  ]
end
```

## Usage

`MdnsLite` is an Elixir/Erlang application, hence it will start up automatically when
its enclosing application starts.

When MdnsLite is running, it can be tested using the linux `dig` utility:

```sh
$ dig @224.0.0.251 -p 5353 -t A nerves-7fcb.local
...
nerves-7fcb.local. 120	IN	A	192.168.0.106
...
$ dig @224.0.0.251 -p 5353 -x 192.168.0.106
...
106.0.168.192.in-addr.arpa. 120	IN	PTR	nerves-7fcb.local.
...
$ dig @nerves-7fcb.local -p 5353 -t PTR _ssh._tcp.local
...
_ssh._tcp.local.	120	IN	PTR	nerves-7fcb._ssh._tcp.local.
nerves-7fcb._ssh._tcp.local. 120 IN	TXT	""
nerves-7fcb._ssh._tcp.local. 120 IN	SRV	0 0 22 nerves-7fcb.local.
nerves-7fcb.local.	120	IN	A	192.168.0.106
...
$ dig @224.0.0.251 -p 5353 -t SRV nerves-7fcb._ssh._tcp.local
...
nerves-7fcb._ssh._tcp.local. 120 IN	SRV	0 0 22 nerves-7fcb.local.
nerves-7fcb.local.	120	IN	A	192.168.0.106
...
```

Although `dig` is a lookup utility for DNS, it can be used to query `MdnsLite`. You can use the reserved ip address (`224.0.0.251`) and port(`5353`) when using `dig` to get mDNS responses. Or you can use the local hostname, e.g., `nerves-7fcb.local` of the host that is providing the mDNS responses along with port`5353`.  

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/mdns_lite](https://hexdocs.pm/mdns_lite).
