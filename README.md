# MdnsLite

[![Hex version](https://img.shields.io/hexpm/v/mdns_lite.svg "Hex version")](https://hex.pm/packages/mdns_lite)
[![CircleCI](https://circleci.com/gh/nerves-networking/mdns_lite.svg?style=svg)](https://circleci.com/gh/nerves-networking/mdns_lite)

MdnsLite is a simple, limited, no frills implementation of an
[mDNS](https://en.wikipedia.org/wiki/Multicast_DNS) (Multicast Domain Name
System) server. It operates like a DNS server, the difference being that it uses
multicast instead of unicast and is meant to be the DNS server for the _.local_
domain. MdnsLite also provides for the advertising (discovery) of services
offered by the host system.  Examples of services are an HTTP or an SSH server.
Read about configuring services in the Configuration section below.

MdnsLite employs a network interface monitor that can dynamically adjust to
network changes, e.g., assignment of a new IP address to a host. MdnsLite
uses [`VintageNet`](https://github.com/nerves-networking/vintage_net) for this.

MdnsLite recognizes the following [query
types](https://en.wikipedia.org/wiki/List_of_DNS_record_types):

* A - Find the IPv4 address of a hostname.
* PTR - Given an IPv4 address, find its hostname - reverse lookup. If, however,
  it receives a request domain of "_services._dns-sd._udp.local", MdnsLite will
  respond with a list of every service available (and is specified in the
  configuration) on the host.
* SRV - Service Locator

If you want to know the details of the various DNS/mDNS record types and their
fields, a good source is
[zytrax.com/books/dns](http://www.zytrax.com/books/dns).

There are at least a couple of other Elixir/Erlang implementations of mDNS servers:

1. [Rosetta Home mdns](https://github.com/rosetta-home/mdns) (Elixir)
2. [Shortishly mdns](https://github.com/shortishly/mdns) (Erlang)

These implementations provided valuable guidance in the building of MdnsLite.

## Configuration

A typical configuration in the `config.exs` file looks like:

```elixir
config :mdns_lite,
  # Use these values to construct the DNS resource record responses
  # to a DNS query.
  host: :hostname,
  ttl: 120,
  services: [
    # service type: _http._tcp.local - used in match
    %{
      id: :web_service,
      protocol: "http",
      transport: "tcp",
      port: 80,
    },
    # service_type: _ssh._tcp.local - used in match
    %{
      id: :ssh_daemon,
      protocol: "ssh",
      transport: "tcp",
      port: 22,
    }
  ]
```

The values of `host` and `ttl` will be used in the construction of mDNS (DNS)
responses.

`host` can have the value of  `:hostname` in which case the value will be
replaced with the value of `:inet.gethostname/0`, otherwise you can provide a
string value. You can specify an alias hostname in which case `host` will be
`["hostname", "alias-example"]`. The second value must be a string. When you use
an alias, an "A" query can be made to  `alias-example.local` as well as to
`hostname.local`. This can also be configured at runtime via
`MdnsLite.set_host/1`:

```elixir
iex> MdnsLite.set_host([:hostname, "nerves"])
:ok
```

`ttl` refers to a Time To Live value in seconds. [RFC 6762 - Multicast
DNS](https://tools.ietf.org/html/rfc6762) - recommends a default value of 120
seconds.

The `services` section lists the services that the host offers, such as
providing an HTTP server. You must supply the `protocol`, `transport` and `port`
values for each service. You may also specify `weight` and/or `host`.  They each
default to a zero value. Please consult the RFC for an explanation of these
values. You can also specify `txt_payload` which is used to define the data in
a TXT DNS resource record, it should be a list of strings containing a key and
value separated by a `=`. Services can be configured in `config.exs` as shown
above, or at runtime:

```elixir
iex> MdnsLite.add_mdns_service(%{
    id: :my_web_server,
    protocol: "http",
    transport: "tcp",
    port: 80,
  })
:ok
iex> MdnsLite.add_mdns_service(%{
    id: :my_ssh_service,
    protocol: "ssh",
    transport: "tcp",
    port: 22,
    txt_payload: ["key=value"],
  })
:ok
```

Services can also be removed at runtime via `remove_mdns_service/1` with the
service id to remove:

```elixir
iex> MdnsLite.remove_mdns_service(:my_web_server)
:ok
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `mdns_lite` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mdns_lite, "~> 0.6"}
  ]
end
```

## DNS Bridge

`MdnsLite` can start a DNS server to respond to `.local` queries. This enables
code that has no knowledge of mDNS to resolve mDNS queries. For example,
Erlang/OTP's built-in DNS resolver doesn't know about mDNS. It's used to resolve
hosts for Erlang distribution and pretty much any code using `:gen_tcp` and
`:gen_udp`. `MdnsLite`'s DNS bridge feature makes `.local` hostname lookups work
for all of this. No code modifications required.

Note that this feature is useful on Nerves devices. Erlang/OTP can use the
system name resolver on desktop Linux and MacOS. The system name resolver should
already be hooked up to an mDNS resolver there.

To set this up, you'll need to enable the DNS bridge on `MdnsLite` and then set
up the DNS resolver to use it first. Here are the options for the application
environment:

```elixir
config :mdns_lite,
  dns_bridge_enabled: true,
  dns_bridge_recursive: true

config :vintage_net,
  additional_name_servers: [{127, 0, 0, 53}]
```

There is currently an issue on Nerves and Linux that you may hit if the
`:mdns_lite` application is not running. The Erlang DNS resolver calls `connect`
to the IP address of the DNS server and then calls `connect` again to the next
one. The second `connect` call fails when the first one is a `127.0.0.x`
address. See [Issue 5092](https://github.com/erlang/otp/issues/5092).

## Debugging

`MdnsLite` maintains a table of records that it advertises and a cache per
network interface. The table of records that it advertises is based solely off
its configuration. Review it by running:

```elixir
iex> MdnsLite.Info.dump_records
<interface_ipv4>.in-addr.arpa: type PTR, class IN, ttl 120, nerves-2e6d.local
<interface_ipv6>.ip6.arpa: type PTR, class IN, ttl 120, nerves-2e6d.local
_epmd._tcp.local: type PTR, class IN, ttl 120, nerves-2e6d._epmd._tcp.local
_services._dns-sd._udp.local: type PTR, class IN, ttl 120, _epmd._tcp.local
_services._dns-sd._udp.local: type PTR, class IN, ttl 120, _sftp-ssh._tcp.local
_services._dns-sd._udp.local: type PTR, class IN, ttl 120, _ssh._tcp.local
_sftp-ssh._tcp.local: type PTR, class IN, ttl 120, nerves-2e6d._sftp-ssh._tcp.local
_ssh._tcp.local: type PTR, class IN, ttl 120, nerves-2e6d._ssh._tcp.local
nerves-2e6d._epmd._tcp.local: type SRV, class IN, ttl 120, priority 0, weight 0, port 4369, nerves-2e6d.local.
nerves-2e6d._epmd._tcp.local: type TXT, class IN, ttl 120,
nerves-2e6d._sftp-ssh._tcp.local: type SRV, class IN, ttl 120, priority 0, weight 0, port 22, nerves-2e6d.local.
nerves-2e6d._sftp-ssh._tcp.local: type TXT, class IN, ttl 120,
nerves-2e6d._ssh._tcp.local: type SRV, class IN, ttl 120, priority 0, weight 0, port 22, nerves-2e6d.local.
nerves-2e6d._ssh._tcp.local: type TXT, class IN, ttl 120,
nerves-2e6d.local: type A, class IN, ttl 120, addr <interface_ipv4>
nerves-2e6d.local: type AAAA, class IN, ttl 120, addr <interface_ipv6>
```

Note that some addresses have not been filled in. They depend on which network
interface receives the query. The idea is that if a computer is looking for you
on the Ethernet interface, you should give records with that Ethernet's
interface rather than, say, the IP address of the WiFi interface.

`MdnsLite`'s cache is filled with records that it sees advertised. It's
basically the same, but can be quite large depending on the mDNS activity on a
link. It looks like this:

```elixir
iex> MdnsLite.Info.dump_caches
Responder: 172.31.112.97
  ...
Responder: 192.168.1.58
  ...
```

## Usage

`MdnsLite` is an Elixir/Erlang application; it will start up automatically when
its enclosing application starts.

When MdnsLite is running, it can be tested using the linux `dig` utility:

```sh
$ dig @224.0.0.251 -p 5353 -t A nerves-7fcb.local
...
nerves-7fcb.local. 120  IN  A 192.168.0.106
...
$ dig @224.0.0.251 -p 5353 -x 192.168.0.106
...
106.0.168.192.in-addr.arpa. 120 IN  PTR nerves-7fcb.local.
...
$ dig @nerves-7fcb.local -p 5353 -t PTR _ssh._tcp.local
...
_ssh._tcp.local.  120 IN  PTR nerves-7fcb._ssh._tcp.local.
nerves-7fcb._ssh._tcp.local. 120 IN TXT "key=value"
nerves-7fcb._ssh._tcp.local. 120 IN SRV 0 0 22 nerves-7fcb.local.
nerves-7fcb.local.  120 IN  A 192.168.0.106
...
$ dig @224.0.0.251 -p 5353 -t SRV nerves-7fcb._ssh._tcp.local
...
nerves-7fcb._ssh._tcp.local. 120 IN SRV 0 0 22 nerves-7fcb.local.
nerves-7fcb.local.  120 IN  A 192.168.0.106
...
```

Although `dig` is a lookup utility for DNS, it can be used to query `MdnsLite`.
You can use the reserved ip address (`224.0.0.251`) and port(`5353`) and query
the local domain. Or you can use the local hostname, e.g., `nerves-7fcb.local`
of the host that is providing the mDNS responses along with port `5353`.

## In memory

[Peter Marks](https://github.com/pcmarks/) wrote and maintained the original
version of `mdns_lite`.
