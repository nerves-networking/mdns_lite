defmodule MdnsLite.Configuration do
  @moduledoc false
  @doc """
  A singleton GenServer. It is responsible for maintaining the various
  configuration values and services that can be specified at runtime and that
  are used to recognize and respond to mDNS requests.
  """
  use GenServer

  defmodule State do
    @type t() :: struct()
    defstruct mdns_config: %{},
              mdns_services: [],
              # Note: Erlang string
              dot_local_name: '',
              ttl: 3600
  end

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec get_mdns_config() :: map()
  def get_mdns_config() do
    GenServer.call(__MODULE__, :get_mdns_config)
  end

  @spec get_mdns_services() :: list()
  def get_mdns_services() do
    GenServer.call(__MODULE__, :get_mdns_services)
  end

  ##############################################################################
  #   GenServer callbacks
  ##############################################################################
  @default_config %{
    host: :hostname,
    ttl: 3600
  }
  @impl true
  def init(_opts) do
    state = %State{
      mdns_config: Application.get_env(:mdns_lite, :mdns_config, @default_config),
      mdns_services: Application.get_env(:mdns_lite, :services, [])
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_mdns_config, _from, state) do
    {:reply, state.mdns_config, state}
  end

  @impl true
  def handle_call(:get_mdns_services, _from, state) do
    {:reply, state.mdns_services, state}
  end
end
