defmodule MdnsLite.Table do
  import MdnsLite.DNS
  alias MdnsLite.{Options, IfInfo}

  @type t :: %{DNS.dns_query() => [DNS.dns_rr()]}

  @moduledoc false

  @spec new(Options.t()) :: t()
  def new(%Options{} = config) do
    %{}
    |> add_a_records(config)
    |> add_ptr_records(config)
    |> add_ptr_records2(config)
    |> add_ptr_records3(config)
    |> add_srv_records(config)
  end

  @spec lookup(t(), DNS.dns_query(), IfInfo.t()) :: [DNS.dns_rr()]
  def lookup(table, query, %IfInfo{} = if_info) do
    normalized = normalize_query(query, if_info)

    Map.get(table, normalized, [])
    |> Enum.map(&fixup_rr(&1, if_info))
  end

  defp normalize_query(dns_query(class: class, type: :ptr, domain: domain) = q, if_info) do
    if domain == ipv4_arpa_address(if_info) do
      dns_query(class: :in, type: :ptr, domain: :ipv4_arpa_address)
    else
      dns_query(q, class: normalize_class(class))
    end
  end

  defp normalize_query(dns_query(domain: domain, type: type, class: class), _if_info) do
    dns_query(domain: domain, type: type, class: normalize_class(class))
  end

  defp normalize_class(32769), do: :in
  defp normalize_class(other), do: other

  defp fixup_rr(dns_rr(class: :in, type: :a, data: :ipv4_address) = rr, if_info) do
    dns_rr(rr, data: if_info.ipv4_address)
  end

  defp fixup_rr(dns_rr(class: :in, type: :ptr, domain: :ipv4_arpa_address) = rr, if_info) do
    dns_rr(rr, domain: ipv4_arpa_address(if_info))
  end

  defp fixup_rr(rr, _if_info) do
    # IO.inspect(dns_rr(rr))
    rr
  end

  defp ipv4_arpa_address(if_info) do
    # Example ARPA address for IP 192.168.0.112 is 112.0.168.192.in-addr.arpa
    arpa_address =
      if_info.ipv4_address
      |> Tuple.to_list()
      |> Enum.reverse()
      |> Enum.join(".")

    to_charlist(arpa_address <> ".in-addr.arpa.")
  end

  defp add_a_records(records, config) do
    for dot_local_name <- config.dot_local_names, into: records do
      {to_dns_query(:in, :a, dot_local_name),
       [to_dns_rr(:in, :a, dot_local_name, config.ttl, :ipv4_address)]}
    end
  end

  defp add_ptr_records(records, %Options{} = config) do
    # services._dns-sd._udp.local. is a special name for
    # "Service Type Enumeration" which is supposed to find all service
    # types on the network. Let them know about ours.
    domain = "_services._dns-sd._udp.local"

    resources =
      Options.get_services(config)
      |> Enum.map(fn service ->
        to_dns_rr(:in, :ptr, domain, config.ttl, to_charlist(service.type <> ".local"))
      end)

    Map.put(records, to_dns_query(:in, :ptr, domain), resources)
  end

  defp add_ptr_records2(records, config) do
    Options.get_services(config)
    |> Enum.group_by(fn service -> service.type <> ".local" end)
    |> Enum.reduce(records, &records_for_service_type(&1, &2, config))
  end

  defp records_for_service_type({domain, services}, records, config) do
    value = Enum.flat_map(services, &service_resources(&1, domain, config))
    Map.put(records, to_dns_query(:in, :ptr, domain), value)
  end

  defp service_resources(service, domain, config) do
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
      to_dns_rr(:in, :a, first_dot_local_name, config.ttl, :ipv4_address)
    ]
  end

  defp add_ptr_records3(records, %Options{} = config) do
    first_dot_local_name = hd(config.dot_local_names)

    Map.put(records, to_dns_query(:in, :ptr, :ipv4_arpa_address), [
      to_dns_rr(:in, :ptr, :ipv4_arpa_address, config.ttl, first_dot_local_name)
    ])
  end

  defp add_srv_records(records, %Options{} = config) do
    Options.get_services(config)
    |> Enum.group_by(fn service -> '#{service.name}.#{service.type}.local' end)
    |> Enum.reduce(records, &srv_records_for_service_type(&1, &2, config))
  end

  defp srv_records_for_service_type({domain, services}, records, config) do
    Map.put(
      records,
      to_dns_query(:in, :srv, domain),
      Enum.flat_map(services, &srv_service_resources(&1, domain, config))
    )
  end

  defp srv_service_resources(service, _domain, config) do
    service_instance_name = "#{service.name}.#{service.type}.local"

    first_dot_local_name = hd(config.dot_local_names)
    target = first_dot_local_name <> "."
    srv_data = {service.priority, service.weight, service.port, to_charlist(target)}

    [
      to_dns_rr(:in, :srv, service_instance_name, config.ttl, srv_data),
      to_dns_rr(:in, :a, first_dot_local_name, config.ttl, :ipv4_address)
    ]
  end

  defp to_dns_query(class, type, domain) do
    dns_query(class: class, type: type, domain: normalize_domain(domain))
  end

  defp to_dns_rr(class, type, domain, ttl, data) do
    dns_rr(
      domain: normalize_domain(domain),
      class: class,
      type: type,
      ttl: ttl,
      data: data
    )
  end

  defp normalize_domain(d) when is_atom(d), do: d
  defp normalize_domain(d), do: to_charlist(d)
end
