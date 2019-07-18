defmodule MdnsLite do
  @moduledoc """
  A simple implementation of an mDNS (multicast DNS (Domain Name Server)) server.
  Rather than accessing a DNS server directly via a well known ip address, mDNS
  is based on multicast UDP. Services listen on a well-known ip address/port. If
  a request arrives that the service can answer, it constructs a DNS response.

  This module creates a GenServer responsible for mainting a set of mDNS servers,
  one per network interface, e.g. "eth0", "lo", etc. These mDNS servers act on behalf of
  the host device that is executing this code. Upon receiving an mDNS request, via
  UDP multicast, these servers respond with host information for this device
  and DNS records about network services that are available from this device.
  SSH and FTP are examples of such services.

  It is initialized with service descriptions. The descriptions will be
  used by the mDNS servers as a response to a matching service query.

  This application can be tested with the linux utility dig:

  ``` dig @224.0.0.251 -p 5353 -t A petes-pt.local```

  The code borrows heavily from the https://hex.pm/packages/mdns package and
  https://github.com/shortishly/mdns.
  """
  require Logger
  use GenServer

  defmodule State do
    @moduledoc """
      A map of interface names to mdns GenServers (MdnsLite.Server).
      And some configuration values that will be used when constructing a DNS
      response packet.
    """
    defstruct ifname_server_map: %{}, mdns_config: %{}, mdns_services: %{}
  end

  @doc """
  Pro forma starting.
  """
  def start_link([_mdns_config, _mdns_services] = opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # default = typical ethernet
  def start_mdns_server(ifname \\ "enp2s0") do
    GenServer.call(__MODULE__, {:start_mdns_server, ifname})
  end

  def stop_mdns_server(ifname) do
    GenServer.call(__MODULE__, {:stop_mdns_server, ifname})
  end

  # TODO REMOVE ME
  def get_state() do
    GenServer.call(__MODULE__, :get_state)
  end

  # TODO REMOVE
  def get_pid(ifname \\ "enp2s0") do
    GenServer.call(__MODULE__, {:get_pid, ifname})
  end

  @doc """
  """
  @impl true
  def init([mdns_config, mdns_services]) do
    {:ok, %State{ifname_server_map: %{}, mdns_config: mdns_config, mdns_services: mdns_services}}
  end

  @impl true
  def handle_call({:start_mdns_server, ifname}, _from, state) do
    with {:ok, server_pid} <-
           MdnsLite.Server.start({ifname, state.mdns_config, state.mdns_services}) do
      Logger.debug("Start mdns server: server_pid #{inspect(server_pid)}")
      new_ifname_server_map = Map.put(state.ifname_server_map, ifname, server_pid)
      {:reply, :ok, %State{state | ifname_server_map: new_ifname_server_map}}
    else
      {:error, reason} ->
        Logger.debug("Start mdns server: #{inspect(reason)}")
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:stop_mdns_server, ifname}, _from, state) do
    new_ifname_server_map =
      case Map.get(state.ifname_server_map, ifname, :not_here) do
        :not_here ->
          state.ifname_server_map

        pid ->
          MdnsLite.Server.stop_server(pid)
          Map.delete(state.ifname_server_map, ifname)
      end

    {:reply, :ok, %State{state | ifname_server_map: new_ifname_server_map}}
  end

  # TODO REMOVE ME
  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # TODO REMOVE ME
  @impl true
  def handle_call({:get_pid, ifname}, _from, state) do
    {:reply, Map.get(state.ifname_server_map, ifname), state}
  end

  ##############################################################################
  #   Private functions
  ##############################################################################
end
