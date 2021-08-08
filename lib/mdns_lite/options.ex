defmodule MdnsLite.Options do
  @moduledoc false

  alias MdnsLite.Service

  @default_host_name_list [:hostname]
  @default_ttl 120
  @default_dns_ip {127, 0, 0, 53}
  @default_dns_port 53
  @default_monitor MdnsLite.VintageNetMonitor
  @default_excluded_ifnames ["lo0", "lo", "ppp0", "wwan0"]
  @default_ipv4_only true

  defstruct services: MapSet.new(),
            dot_local_names: [],
            hosts: [],
            ttl: @default_ttl,
            dns_bridge_enabled: false,
            dns_bridge_ip: @default_dns_ip,
            dns_bridge_port: @default_dns_port,
            dns_bridge_recursive: true,
            if_monitor: @default_monitor,
            excluded_ifnames: @default_excluded_ifnames,
            ipv4_only: @default_ipv4_only

  @type t :: %__MODULE__{
          services: MapSet.t(map()),
          dot_local_names: [String.t()],
          hosts: [charlist()],
          ttl: pos_integer(),
          dns_bridge_enabled: boolean(),
          dns_bridge_ip: :inet.address(),
          dns_bridge_port: 1..65535,
          dns_bridge_recursive: boolean(),
          if_monitor: module(),
          excluded_ifnames: [String.t()],
          ipv4_only: boolean()
        }

  @spec from_application_env() :: t()
  def from_application_env() do
    hosts = Application.get_env(:mdns_lite, :host, @default_host_name_list)
    ttl = Application.get_env(:mdns_lite, :ttl, @default_ttl)
    config_services = Application.get_env(:mdns_lite, :services, [])
    dns_bridge_enabled = Application.get_env(:mdns_lite, :dns_bridge_enabled, false)
    dns_bridge_ip = Application.get_env(:mdns_lite, :dns_bridge_ip, @default_dns_ip)
    dns_bridge_port = Application.get_env(:mdns_lite, :dns_bridge_port, @default_dns_port)
    dns_bridge_recursive = Application.get_env(:mdns_lite, :dns_bridge_recursive, true)
    if_monitor = Application.get_env(:mdns_lite, :if_monitor, @default_monitor)
    ipv4_only = Application.get_env(:mdns_lite, :ipv4_only, @default_ipv4_only)

    excluded_ifnames =
      Application.get_env(:mdns_lite, :excluded_ifnames, @default_excluded_ifnames)

    %__MODULE__{
      ttl: ttl,
      dns_bridge_enabled: dns_bridge_enabled,
      dns_bridge_ip: dns_bridge_ip,
      dns_bridge_port: dns_bridge_port,
      dns_bridge_recursive: dns_bridge_recursive,
      if_monitor: if_monitor,
      excluded_ifnames: excluded_ifnames,
      ipv4_only: ipv4_only
    }
    |> add_hosts(hosts)
    |> add_services(config_services)
  end

  @spec defaults() :: t()
  def defaults() do
    %__MODULE__{}
    |> add_hosts(@default_host_name_list)
  end

  @spec add_service(t(), map()) :: t()
  def add_service(options, service) when is_map(service) do
    add_services(options, [service])
  end

  @spec add_services(t(), [map()]) :: t()
  def add_services(%__MODULE__{} = options, services) do
    updated =
      services
      |> Enum.map(&Service.new/1)
      |> Enum.reduce(options.services, &MapSet.put(&2, &1))

    %{options | services: updated}
  end

  @spec get_services(t()) :: [Service.t()]
  def get_services(%__MODULE__{} = options) do
    MapSet.to_list(options.services)
  end

  @spec remove_service_by_name(t(), String.t()) :: t()
  def remove_service_by_name(%__MODULE__{} = options, service_name)
      when is_binary(service_name) do
    services_set =
      options.services
      |> Enum.reject(&(&1.name == service_name))
      |> MapSet.new()

    %{options | services: services_set}
  end

  @spec set_host(t(), String.t() | :hostname) :: t()
  def set_host(%__MODULE__{} = options, host) do
    resolved_host = resolve_mdns_name(host)
    dot_local_name = "#{resolved_host}.local"

    %{options | dot_local_names: [dot_local_name], hosts: [resolved_host]}
  end

  @spec add_host(t(), String.t() | :hostname) :: t()
  def add_host(%__MODULE__{} = options, host) do
    resolved_host = resolve_mdns_name(host)
    dot_local_name = "#{resolved_host}.local"

    %{
      options
      | dot_local_names: options.dot_local_names ++ [dot_local_name],
        hosts: options.hosts ++ [resolved_host]
    }
  end

  @spec add_hosts(t(), [String.t() | :hostname]) :: t()
  def add_hosts(%__MODULE__{} = options, hosts) do
    Enum.reduce(hosts, options, &add_host(&2, &1))
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
