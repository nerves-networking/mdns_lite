defmodule MdnsLite do
  @moduledoc """
  A simple implementation of an mDNS (multicast DNS (Domain Name Server)) server.
  Rather than accessing a DNS server directly, mDNS
  is based on multicast UDP. Hosts/services listen on a well-known ip address/port. If
  a request arrives that the service can answer, it constructs the appropriate DNS response.

  This module runs as a GenServer responsible for maintaining a set of mDNS servers. The intent
  is to have one server per network interface, e.g. "eth0", "lo", etc. Upon
  receiving an mDNS request, these servers respond with mDNS (DNS) records with
  host information for the host this module is running on. Also there will be
  SRV (service) DNS records about network services that are available from this device.
  SSH and FTP are examples of such services.

  Note: the mDNS servers can be run directly. This module serves as a convenience
  for apps that are dealing with multiple network interfaces.

  This module is initialized with host information and service descriptions.
  The descriptions will be used by the mDNS servers as a response to a matching service query.

  Please refer to the README for further information.

  This package can be tested with the linux utility dig:

  ``` dig @224.0.0.251 -p 5353 -t A petes-pt.local```

  The code borrows heavily from [mdns](https://hex.pm/packages/mdns) and
  [shortishly's mdns](https://github.com/shortishly/mdns) packages.
  """

  alias MdnsLite.{Responder, ResponderSupervisor}

  require Logger

  @doc """
  Start an mDNS server for a network interface
  """
  @spec start_mdns_server(ifname :: String.t()) :: DynamicSupervisor.on_start_child()
  def start_mdns_server(ifname) do
    ResponderSupervisor.start_child(ifname)
  end

  @doc """
  Stop the mDNS server for a network interface
  """
  @spec stop_mdns_server(ifname :: String.t()) :: :ok
  def stop_mdns_server(ifname) do
    Responder.stop_server(ifname)
  end
end
