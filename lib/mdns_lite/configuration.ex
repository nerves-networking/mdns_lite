defmodule MdnsLite.Configuration do
  use GenServer

  alias MdnsLite.ResponderSupervisor

  @moduledoc false

  # A singleton GenServer. It is responsible for maintaining the various
  # configuration values and services that can be specified at runtime and that
  # are used to recognize and respond to mDNS requests.

  defmodule State do
    @moduledoc false

    defstruct mdns_config: %{},
              mdns_services: MapSet.new(),
              # Note: Erlang string
              dot_local_name: '',
              host_name_alias: '',
              ttl: 120

    @type t :: %__MODULE__{
            mdns_config: map(),
            mdns_services: MapSet.t(map()),
            dot_local_name: charlist(),
            ttl: pos_integer()
          }
  end

  @default_host_name_list [:hostname]
  @default_ttl 120
  @default_service %{
    weight: 0,
    priority: 0,
    txt_payload: [""]
  }

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec add_mdns_services(map() | [map()]) :: :ok
  def add_mdns_services(service) when is_map(service) do
    add_mdns_services([service])
  end

  def add_mdns_services(services) do
    GenServer.call(__MODULE__, {:add_services, services})
  end

  @spec get_mdns_config() :: map()
  def get_mdns_config() do
    GenServer.call(__MODULE__, :get_mdns_config)
  end

  @spec get_mdns_services() :: [map()]
  def get_mdns_services() do
    GenServer.call(__MODULE__, :get_mdns_services)
  end

  @spec remove_mdns_services(String.t() | [String.t()]) :: :ok
  def remove_mdns_services(service_name) when is_bitstring(service_name) do
    remove_mdns_services([service_name])
  end

  def remove_mdns_services(service_names) do
    GenServer.call(__MODULE__, {:remove_services, service_names})
  end

  @spec set_host(String.t() | [String.t() | :hostname] | :hostname) :: :ok | {:error, String.t()}
  def set_host(host) when is_binary(host) or is_list(host) or host == :hostname do
    GenServer.call(__MODULE__, {:set_host, host})
  end

  def set_host(host) do
    {:error, "must be a host or list [hostname, alias]. Got: #{inspect(host)}"}
  end

  ##############################################################################
  #   GenServer callbacks
  ##############################################################################
  @impl true
  def init(_opts) do
    env_host = Application.get_env(:mdns_lite, :host, @default_host_name_list)
    hosts = configure_hosts(env_host)

    ttl = Application.get_env(:mdns_lite, :ttl, @default_ttl)

    config_services = Application.get_env(:mdns_lite, :services, [])

    state = %State{
      mdns_config: %{host: List.first(hosts), host_name_alias: Enum.at(hosts, 1), ttl: ttl}
    }

    {:ok, add_services(config_services, state)}
  end

  @impl true
  def handle_call({:add_services, services}, _from, state) do
    {:reply, :ok, add_services(services, state), {:continue, :refresh_responders}}
  end

  def handle_call(:get_mdns_config, _from, state) do
    {:reply, state.mdns_config, state}
  end

  @impl true
  def handle_call(:get_mdns_services, _from, state) do
    {:reply, MapSet.to_list(state.mdns_services), state}
  end

  def handle_call({:remove_services, service_names}, _from, state) do
    {:reply, :ok, remove_services(service_names, state), {:continue, :refresh_responders}}
  end

  def handle_call({:set_host, host}, _from, %{mdns_config: mdns_config} = state) do
    hosts = configure_hosts(host)
    mdns_config = %{mdns_config | host: hd(hosts), host_name_alias: Enum.at(hosts, 1)}
    {:reply, :ok, %{state | mdns_config: mdns_config}, {:continue, :refresh_responders}}
  end

  @impl true
  def handle_continue(:refresh_responders, state) do
    :ok =
      Map.take(state, [:mdns_config, :mdns_services])
      |> Map.to_list()
      |> ResponderSupervisor.refresh_children()

    {:noreply, state}
  end

  ##############################################################################
  #  Private functions
  ##############################################################################
  defp add_service(service, services_set) do
    # Merge a service's default values and construct type string that is used in
    # Query comparisons
    formatted =
      Map.merge(@default_service, service)
      |> Map.put(:type, "_#{service.protocol}._#{service.transport}")

    MapSet.put(services_set, formatted)
  end

  defp add_services(services, %{mdns_services: services_set} = state) do
    updated = Enum.reduce(services, services_set, &add_service/2)
    %{state | mdns_services: updated}
  end

  defp configure_hosts(nil) do
    @default_host_name_list
  end

  defp configure_hosts(env_host) when is_list(env_host) do
    env_host
  end

  defp configure_hosts(env_host) do
    [env_host]
  end

  defp remove_services(service_names, %{mdns_services: services_set} = state) do
    services_set =
      services_set
      |> Enum.reject(&(&1.name in service_names))
      |> MapSet.new()

    %{state | mdns_services: services_set}
  end
end
