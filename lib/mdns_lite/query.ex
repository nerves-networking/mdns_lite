defmodule MdnsLite.Query do
  require Logger

  alias MdnsLite.Configuration

  @moduledoc false

  @doc """
  Decompose a DNS Query.

  This function returns a list of DNS Resource Records that should be sent back
  to the querier. The following query types are recognized: A, PTR, and SRV.
  """
  @spec handle(DNS.Query.t(), map()) :: [DNS.Resource.t()]

  # An "A" type query. Address mapping record. Return the IP address if
  # this host's local name or alias, if specified, matches the query domain.
  def handle(%DNS.Query{class: :in, type: :a, domain: domain} = _query, state) do
    cond do
      state.dot_local_name == domain ->
        [
          dns_resource(:a, state.dot_local_name, state.ttl, state.ip)
        ]

      state.dot_alias_name == domain ->
        [
          dns_resource(:a, state.dot_alias_name, state.ttl, state.ip)
        ]

      true ->
        []
    end
  end

  # A "PTR" type query. There are three different responses depending on the
  # domain value of the query:
  # 1. A "special" domain value of "_services._dns-sd._udp.local" - DNS-SD
  # 2. A specific service domain, e.g., "_ssh._tcp.local"
  # 3. Reverse address lookup. Return the hostname for a matching IP address,
  def handle(
        %DNS.Query{class: :in, type: :ptr, domain: domain} = _query,
        state
      ) do
    # Convert our IP address so as to be able to match the arpa address
    # in the query. ARPA address for IP 192.168.0.112 is 112.0.168.192.in-addr.arpa
    arpa_address =
      state.ip
      |> Tuple.to_list()
      |> Enum.reverse()
      |> Enum.join(".")

    cond do
      domain == '_services._dns-sd._udp.local' ->
        # _ = Logger.debug("DNS PTR RECORD for interface at #{inspect(state.ip)} for DNS-SD")
        # services._dns-sd._udp.local. is a special name for
        # "Service Type Enumeration" which is supposed to find all service
        # types on the network. Let them know about ours.
        Configuration.get_mdns_services()
        |> Enum.flat_map(fn service ->
          [
            dns_resource(:ptr, domain, state.ttl, to_charlist(service.type <> ".local"))
          ]
        end)

      # Something is looking for a specific service. Can we offer this service?
      String.starts_with?(to_string(domain), "_") ->
        Configuration.get_mdns_services()
        |> Enum.filter(fn service ->
          to_string(domain) == service.type <> ".local"
        end)
        |> Enum.flat_map(fn service ->
          service_instance_name =
            String.to_charlist("#{state.instance_name}.#{service.type}.local")

          target = state.dot_local_name ++ '.'
          srv_data = {service.priority, service.weight, service.port, target}

          [
            dns_resource(:ptr, domain, state.ttl, service_instance_name),
            # Until we support the user specification of TXT values,
            # the RFC says at a minimum return a TXT record with an empty string
            dns_resource(:txt, service_instance_name, state.ttl, [""]),
            dns_resource(:srv, service_instance_name, state.ttl, srv_data),
            dns_resource(:a, state.dot_local_name, state.ttl, state.ip)
          ]
        end)

      # Reverse domain lookup. Only need to match the beginning characters
      String.starts_with?(to_string(domain), arpa_address) ->
        full_arpa_address = to_charlist(arpa_address <> ".in-addr.arpa.")

        [dns_resource(:ptr, full_arpa_address, state.ttl, state.dot_local_name)]

      true ->
        []
    end
  end

  # An "SRV" type query. Find services, e.g., HTTP, SSH. The domain field in a
  # SRV service query will look like: "<host name>._http._tcp.local".
  # Respond only on an exact # match
  def handle(
        %DNS.Query{class: :in, type: :srv, domain: domain} = _query,
        state
      ) do
    state.services
    |> Enum.filter(fn service ->
      instance_service_name = "#{state.instance_name}.#{service.type}.local"
      to_string(domain) == instance_service_name
    end)
    |> Enum.flat_map(fn service ->
      # construct the data value to be returned
      # Note: The spec - RFC 2782 - specifies that the target/hostname end with a dot.
      service_instance_name = String.to_charlist("#{state.instance_name}.#{service.type}.local")

      target = state.dot_local_name ++ '.'
      srv_data = {service.priority, service.weight, service.port, target}

      [
        dns_resource(:srv, service_instance_name, state.ttl, srv_data),
        dns_resource(:a, state.dot_local_name, state.ttl, state.ip)
      ]
    end)
  end

  # Ignore any other type of query
  def handle(_query, _state) do
    []
  end

  defp dns_resource(type, domain, ttl, data) do
    %DNS.Resource{
      domain: domain,
      class: :in,
      type: type,
      ttl: ttl,
      data: data
    }
  end
end
