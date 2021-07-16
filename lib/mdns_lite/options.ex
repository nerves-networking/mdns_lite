defmodule MdnsLite.Options do
  @moduledoc false

  alias MdnsLite.Service

  @default_host_name_list [:hostname]
  @default_ttl 120

  defstruct services: MapSet.new(),
            dot_local_names: [],
            hosts: [],
            ttl: @default_ttl

  @type t :: %__MODULE__{
          services: MapSet.t(map()),
          dot_local_names: [String.t()],
          hosts: [charlist()],
          ttl: pos_integer()
        }

  @spec from_application_env() :: t()
  def from_application_env() do
    hosts = Application.get_env(:mdns_lite, :host, @default_host_name_list)
    ttl = Application.get_env(:mdns_lite, :ttl, @default_ttl)
    config_services = Application.get_env(:mdns_lite, :services, [])

    %__MODULE__{ttl: ttl}
    |> add_hosts(hosts)
    |> add_services(config_services)
  end

  @spec defaults() :: t()
  def defaults() do
    %__MODULE__{ttl: @default_ttl}
    |> add_hosts(@default_host_name_list)
  end

  @spec add_service(t(), map()) :: t()
  def add_service(state, service) when is_map(service) do
    add_services(state, [service])
  end

  @spec add_services(t(), [map()]) :: t()
  def add_services(%__MODULE__{} = state, services) do
    updated =
      services
      |> Enum.map(&Service.new/1)
      |> Enum.reduce(state.services, &MapSet.put(&2, &1))

    %{state | services: updated}
  end

  @spec get_services(t()) :: [Service.t()]
  def get_services(%__MODULE__{} = state) do
    MapSet.to_list(state.services)
  end

  @spec remove_service_by_name(t(), String.t()) :: t()
  def remove_service_by_name(%__MODULE__{} = state, service_name) when is_binary(service_name) do
    services_set =
      state.services
      |> Enum.reject(&(&1.name == service_name))
      |> MapSet.new()

    %{state | services: services_set}
  end

  @spec set_host(t(), String.t() | :hostname) :: t()
  def set_host(%__MODULE__{} = state, host) do
    resolved_host = resolve_mdns_name(host)
    dot_local_name = "#{resolved_host}.local"

    %{state | dot_local_names: [dot_local_name], hosts: [resolved_host]}
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

  defp resolve_mdns_name(mdns_name) when is_binary(mdns_name), do: mdns_name

  defp resolve_mdns_name(_other) do
    raise RuntimeError, "Host must be :hostname or a string"
  end
end
