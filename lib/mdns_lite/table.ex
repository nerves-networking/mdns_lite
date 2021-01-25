defmodule MdnsLite.Table do
  alias MdnsLite.{Config, IfInfo}

  import Record, only: [defrecord: 2]

  defrecord :dns_query, Record.extract(:dns_query, from_lib: "kernel/src/inet_dns.hrl")
  defrecord :dns_rr, Record.extract(:dns_rr, from_lib: "kernel/src/inet_dns.hrl")

  @type dns_query :: record(:dns_query, [])
  @type dns_rr :: record(:dns_rr, [])

  @moduledoc false

  @spec to_table(Config.t(), IfInfo.t()) :: map()
  def to_table(%Config{} = config, %IfInfo{} = if_info) do
    %{}
    |> a_records(config, if_info)
    |> ptr_records(config, if_info)
    |> ptr_records2(config, if_info)
    |> ptr_records3(config, if_info)
    |> srv_records(config, if_info)
  end

  defp a_records(records, %Config{} = config, if_info) do
    for dot_local_name <- config.dot_local_names, into: records do
      {to_dns_query(:in, :a, dot_local_name),
       [to_dns_rr(:in, :a, dot_local_name, config.ttl, if_info.ipv4_address)]}
    end
  end

  defp ptr_records(records, %Config{} = config, _if_info) do
    # services._dns-sd._udp.local. is a special name for
    # "Service Type Enumeration" which is supposed to find all service
    # types on the network. Let them know about ours.
    domain = "_services._dns-sd._udp.local"

    resources =
      Config.get_mdns_services(config)
      |> Enum.map(fn service ->
        to_dns_rr(:in, :ptr, domain, config.ttl, to_charlist(service.type <> ".local"))
      end)

    Map.put(records, to_dns_query(:in, :ptr, domain), resources)
  end

  defp ptr_records2(records, %Config{} = config, if_info) do
    Config.get_mdns_services(config)
    |> Enum.group_by(fn service -> service.type <> ".local" end)
    |> Enum.reduce(records, &records_for_service_type(&1, &2, config, if_info))
  end

  defp records_for_service_type({domain, services}, records, config, if_info) do
    value = Enum.flat_map(services, &service_resources(&1, domain, config, if_info))
    Map.put(records, to_dns_query(:in, :ptr, domain), value)
  end

  defp service_resources(service, domain, config, if_info) do
    service_instance_name = to_charlist("#{service.name}.#{service.type}.local")

    first_dot_local_name = hd(config.dot_local_names)
    target = first_dot_local_name <> "."
    srv_data = {service.priority, service.weight, service.port, to_charlist(target)}

    [
      to_dns_rr(:in, :ptr, domain, config.ttl, service_instance_name),
      to_dns_rr(
        :in,
        :txt,
        service_instance_name,
        config.ttl,
        to_charlist(service.txt_payload)
      ),
      to_dns_rr(:in, :srv, service_instance_name, config.ttl, srv_data),
      to_dns_rr(:in, :a, first_dot_local_name, config.ttl, if_info.ipv4_address)
    ]
  end

  def ptr_records3(records, %Config{} = config, if_info) do
    # Convert our IP address so as to be able to match the arpa address
    # in the query. ARPA address for IP 192.168.0.112 is 112.0.168.192.in-addr.arpa
    arpa_address =
      if_info.ipv4_address
      |> Tuple.to_list()
      |> Enum.reverse()
      |> Enum.join(".")

    full_arpa_address = to_charlist(arpa_address <> ".in-addr.arpa.")
    first_dot_local_name = hd(config.dot_local_names)

    Map.put(records, to_dns_query(:in, :ptr, full_arpa_address), [
      to_dns_rr(:in, :ptr, full_arpa_address, config.ttl, first_dot_local_name)
    ])
  end

  def srv_records(records, %Config{} = config, if_info) do
    Config.get_mdns_services(config)
    |> Enum.group_by(fn service -> '#{service.name}.#{service.type}.local' end)
    |> Enum.reduce(records, &srv_records_for_service_type(&1, &2, config, if_info))
  end

  defp srv_records_for_service_type({domain, services}, records, config, if_info) do
    Map.put(
      records,
      to_dns_query(:in, :srv, domain),
      Enum.flat_map(services, &srv_service_resources(&1, domain, config, if_info))
    )
  end

  defp srv_service_resources(service, _domain, config, if_info) do
    service_instance_name = "#{service.name}.#{service.type}.local"

    first_dot_local_name = hd(config.dot_local_names)
    target = first_dot_local_name <> "."
    srv_data = {service.priority, service.weight, service.port, to_charlist(target)}

    [
      to_dns_rr(:in, :srv, service_instance_name, config.ttl, srv_data),
      to_dns_rr(:in, :a, first_dot_local_name, config.ttl, if_info.ipv4_address)
    ]
  end

  defp to_dns_query(class, type, domain) do
    dns_query(class: class, type: type, domain: to_charlist(domain))
  end

  defp to_dns_rr(class, type, domain, ttl, data) do
    dns_rr(
      domain: to_charlist(domain),
      class: class,
      type: type,
      ttl: ttl,
      data: data
    )
  end
end
