defmodule MdnsLite.Query do
  require Logger

  alias MdnsLite.Configuration
  import Record, only: [defrecord: 2]

  defrecord :dns_query, Record.extract(:dns_query, from_lib: "kernel/src/inet_dns.hrl")
  defrecord :dns_rr, Record.extract(:dns_rr, from_lib: "kernel/src/inet_dns.hrl")

  @type dns_query :: record(:dns_query, [])
  @type dns_resource :: record(:dns_rr, [])

  @moduledoc false

  @doc """
  Decompose a DNS Query.

  This function returns a list of DNS Resource Records that should be sent back
  to the querier. The following query types are recognized: A, PTR, and SRV.
  """
  @spec handle(dns_query, map()) :: [dns_resource]

  @in_class [:in, 32769]

  # An "A" type query. Address mapping record. Return the IP address if
  # this host's local name or alias, if specified, matches the query domain.
  def handle(dns_query(domain: domain, class: class, type: :a), state) when class in @in_class do
    cond do
      state.dot_local_name == domain ->
        [
          dns_rr(
            class: :in,
            type: :a,
            domain: state.dot_local_name,
            ttl: state.ttl,
            data: state.ip
          )
        ]

      state.dot_alias_name == domain ->
        [
          dns_rr(
            class: :in,
            type: :a,
            domain: state.dot_alias_name,
            ttl: state.ttl,
            data: state.ip
          )
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
  def handle(dns_query(domain: domain, class: class, type: :ptr), state)
      when class in @in_class do
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
            dns_rr(
              class: :in,
              type: :ptr,
              domain: domain,
              ttl: state.ttl,
              data: to_charlist(service.type <> ".local")
            )
          ]
        end)

      # Something is looking for a specific service. Can we offer this service?
      String.starts_with?(to_string(domain), "_") ->
        Configuration.get_mdns_services()
        |> Enum.filter(fn service ->
          to_string(domain) == service.type <> ".local"
        end)
        |> Enum.flat_map(fn service ->
          service_instance_name = String.to_charlist("#{service.name}.#{service.type}.local")

          target = state.dot_local_name ++ '.'
          srv_data = {service.priority, service.weight, service.port, target}

          [
            dns_rr(
              class: :in,
              type: :ptr,
              domain: domain,
              ttl: state.ttl,
              data: service_instance_name
            ),
            dns_rr(
              class: :in,
              type: :txt,
              domain: service_instance_name,
              ttl: state.ttl,
              data: service.txt_payload
            ),
            dns_rr(
              class: :in,
              type: :srv,
              domain: service_instance_name,
              ttl: state.ttl,
              data: srv_data
            ),
            dns_rr(
              class: :in,
              type: :a,
              domain: state.dot_local_name,
              ttl: state.ttl,
              data: state.ip
            )
          ]
        end)

      # Reverse domain lookup. Only need to match the beginning characters
      String.starts_with?(to_string(domain), arpa_address) ->
        full_arpa_address = to_charlist(arpa_address <> ".in-addr.arpa.")

        [
          dns_rr(
            class: :in,
            type: :ptr,
            domain: full_arpa_address,
            ttl: state.ttl,
            data: state.dot_local_name
          )
        ]

      true ->
        []
    end
  end

  # An "SRV" type query. Find services, e.g., HTTP, SSH. The domain field in a
  # SRV service query will look like: "<host name>._http._tcp.local".
  # Respond only on an exact # match
  def handle(dns_query(domain: domain, class: class, type: :srv), state)
      when class in @in_class do
    state.services
    |> Enum.filter(fn service ->
      instance_service_name = "#{service.name}.#{service.type}.local"
      to_string(domain) == instance_service_name
    end)
    |> Enum.flat_map(fn service ->
      # construct the data value to be returned
      # Note: The spec - RFC 2782 - specifies that the target/hostname end with a dot.
      service_instance_name = String.to_charlist("#{service.name}.#{service.type}.local")

      target = state.dot_local_name ++ '.'
      srv_data = {service.priority, service.weight, service.port, target}

      [
        dns_rr(
          class: :in,
          type: :srv,
          domain: service_instance_name,
          ttl: state.ttl,
          data: srv_data
        ),
        dns_rr(class: :in, type: :a, domain: state.dot_local_name, ttl: state.ttl, data: state.ip)
      ]
    end)
  end

  # Ignore any other type of query
  def handle(_query, _state) do
    []
  end
end
