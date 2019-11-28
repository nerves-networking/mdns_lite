defmodule MdnsLite do
  @moduledoc """
  A simple implementation of an mDNS (multicast DNS (Domain Name Server)) server.
  mDNS uses multicast UDP rather than TCP. Its primary use is to provide DNS
  support for the `local` domain. `MdnsLite` listens on a well-known ip address/port. If
  a request arrives that it recognizes, it constructs the appropriate DNS response.


  `MdnsLite` responds to a limited number of DNS requests; they are all handled
  in the `MdnsLite.Query` module. Of particular note is the SRV request. The
  response will be a list of known services and how to contact them (domain and port)
  as described in the configuration file.

  `MdnsLite` uses a "network monitor", a module that listens for changes in a network.
  Its purpose is to ensure that the network interfaces are up to date. The current
  version of `MdnsLite` has an `MdnsLite.InetMonitor` which periodically checks,
  via `inet:getifaddrs()`,
  for changes in the network. For example, a change could be the re-assignment of IP addresses.

  This module is initialized, at runtime, with host information and service descriptions found
  in the `config.exs` file.  The descriptions will be used by `MdnsLite` to
  construct a response to a query.

  Please refer to the `README.md` for further information.

  """
  defdelegate add_mdns_services(services), to: MdnsLite.Configuration
  defdelegate remove_mdns_services(service_names), to: MdnsLite.Configuration
  defdelegate set_host(host), to: MdnsLite.Configuration
end
