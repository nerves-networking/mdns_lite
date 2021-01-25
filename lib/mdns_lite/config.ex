defmodule MdnsLite.Config do
  @moduledoc false

  defstruct mdns_services: MapSet.new(),
            dot_local_names: [],
            hosts: [],
            ttl: 120

  @type t :: %__MODULE__{
          mdns_services: MapSet.t(map()),
          dot_local_names: [String.t()],
          hosts: [charlist()],
          ttl: pos_integer()
        }

  @default_host_name_list [:hostname]
  @default_ttl 120
  @default_service %{
    weight: 0,
    priority: 0,
    txt_payload: [""]
  }

  @spec from_application_env() :: t()
  def from_application_env() do
    hosts = Application.get_env(:mdns_lite, :host, @default_host_name_list)
    ttl = Application.get_env(:mdns_lite, :ttl, @default_ttl)
    config_services = Application.get_env(:mdns_lite, :services, [])

    %__MODULE__{ttl: ttl}
    |> add_hosts(hosts)
    |> add_mdns_services(config_services)
  end

  @spec add_mdns_services(t(), map() | [map()]) :: t()
  def add_mdns_services(state, service) when is_map(service) do
    add_mdns_services(state, [service])
  end

  def add_mdns_services(%__MODULE__{mdns_services: services_set} = state, services) do
    updated = Enum.reduce(services, services_set, &add_service/2)
    %{state | mdns_services: updated}
  end

  defp add_service(service, services_set) do
    # Merge a service's default values and construct type string that is used in
    # Query comparisons
    formatted =
      Map.merge(@default_service, service)
      |> Map.put(:type, "_#{service.protocol}._#{service.transport}")

    MapSet.put(services_set, formatted)
  end

  @spec get_mdns_services(t()) :: [map()]
  def get_mdns_services(state) do
    MapSet.to_list(state.mdns_services)
  end

  @spec remove_mdns_services(t(), String.t() | [String.t()]) :: t()
  def remove_mdns_services(state, service_name) when is_bitstring(service_name) do
    remove_mdns_services(state, [service_name])
  end

  def remove_mdns_services(%__MODULE__{mdns_services: services_set} = state, service_names) do
    services_set =
      services_set
      |> Enum.reject(&(&1.name in service_names))
      |> MapSet.new()

    %{state | mdns_services: services_set}
  end

  @spec add_host(t(), String.t() | :hostname) :: t()
  def add_host(%__MODULE__{} = state, host) do
    resolved_host = resolve_mdns_name(host)
    dot_local_name = "#{resolved_host}.local"

    %{
      state
      | dot_local_names: state.dot_local_names ++ [dot_local_name],
        hosts: state.hosts ++ [resolved_host]
    }
  end

  @spec add_hosts(t(), [String.t() | :hostname]) :: t()
  def add_hosts(%__MODULE__{} = state, hosts) do
    Enum.reduce(hosts, state, &add_host(&2, &1))
  end

  defp resolve_mdns_name(:hostname) do
    {:ok, hostname} = :inet.gethostname()
    hostname |> to_string
  end

  defp resolve_mdns_name(mdns_name), do: mdns_name
end
