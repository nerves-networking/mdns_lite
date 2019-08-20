defmodule MdnsLite.Query do
  require Logger

  alias MdnsLite.Configuration

  @moduledoc false

  @doc """
  Handle a DNS Query

  This function returns a list of DNS Resource Records that should be sent back
  to the querier. The list is dependent on the query type, e.g., PTR, SRV, etc.
  """
  @spec handle(DNS.Query.t(), map()) :: [DNS.Resource.t()]

  # An "A" type query. Address mapping record. Return the IP address if
  # this host name matches the query domain.
  def handle(%DNS.Query{class: :in, type: :a, domain: domain} = _query, state) do
    case state.dot_local_name == domain do
      true ->
        _ = Logger.debug("DNS A RECORD for interface at #{inspect(state.ip)}")

        [
          %DNS.Resource{
            class: :in,
            type: :a,
            ttl: state.ttl,
            domain: state.dot_local_name,
            data: state.ip
          }
        ]

      _ ->
        []
    end
  end

  # A "PTR" type query. Reverse address lookup. Return the hostname of an
  # IP address and a "special" case that recognizes a special domain
  # "_services._dns-sd._udp.local" - DNS-SD
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
      # Only need to match the beginning characters
      String.starts_with?(to_string(domain), arpa_address) ->
        _ = Logger.debug("DNS PTR RECORD for interface at #{inspect(state.ip)}")

        resource_record = %DNS.Resource{
          class: :in,
          type: :ptr,
          ttl: state.ttl,
          data: state.dot_local_name
        }

        [resource_record]

      domain == '_services._dns-sd._udp.local' ->
        _ = Logger.debug("DNS PTR RECORD for interface at #{inspect(state.ip)} for DNS-SD")
        # services._dns-sd._udp.local. is a special name for
        # "Service Type Enumeration" which is supposed to find all service
        # types on the network. Let them know about ours.
        Configuration.get_mdns_services()
        |> Enum.map(fn service ->
          %DNS.Resource{
            domain: domain,
            class: :in,
            type: :ptr,
            ttl: state.ttl,
            data: to_charlist(service.type <> ".local")
          }
        end)

      true ->
        []
    end
  end

  # A "SRV" type query. Find services, e.g., HTTP, SSH. The domain field in a
  # SRV service query will look like "_http._tcp.local". Respond only on an exact
  # match
  def handle(
        %DNS.Query{class: :in, type: :srv, domain: domain} = _query,
        state
      ) do
    state.services
    |> Enum.filter(fn service ->
      local_service = service.type <> ".local"
      to_string(domain) == local_service
    end)
    |> Enum.map(fn service ->
      _ = Logger.debug("DNS SRV RECORD for interface at #{inspect(state.ip)}")
      # construct the data value to be returned
      # Note: The spec - RFC 2782 - specifies that the target/hostname end with a dot.
      target = state.dot_local_name ++ '.'
      data = {service.priority, service.weight, service.port, target}

      %DNS.Resource{
        class: :in,
        type: :srv,
        ttl: state.ttl,
        data: data
      }
    end)
  end

  # Ignore any other type of query
  def handle(%DNS.Query{class: class, type: type} = _query, state) do
    _ =
      Logger.debug(
        "IGNORING #{inspect(class)} #{inspect(type)} DNS RECORD for interface at #{
          inspect(state.ip)
        }"
      )

    []
  end
end
