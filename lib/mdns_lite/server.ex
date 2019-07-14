defmodule MdnsLite.Server do
  @moduledoc """
  A GenServer that is responsible for responding to a limited number of mDNS
  requests (queries). A UDP port is opened on the mDNS reserved IP/port. Any
  UDP packets will be caught by handle_info() but only a subset of them are
  of interest.

  For an 'A' type query - address mapping: If the query domain equals this
  server's hostname, respond with an 'A' type resource containing an IP address.

  For a 'PTR' type query - reverse UOP lookup: Given an IP address and it
  matches the server's IP address, respond with the hostname.

  'SRV' service queries.

  There is one of these servers for every network interface (managed by
  MdnsLite.
  """

  use GenServer
  require Logger

  # Reserved ip address and port for mDNS
  @mdns_ip Application.get_env(:mdns_lite, :mdns_ip)
  @mdns_port Application.get_env(:mdns_lite, :mdns_port)

  # A Standard DNS response packet
  @response_packet %DNS.Record{
    header: %DNS.Header{
      aa: true,
      qr: true,
      opcode: :query,
      rcode: 0
    },
    # A list of answer entries. Can be empty.
    anlist: [],
    # A list of resource entries. Can be empty.
    arlist: []
  }

  defmodule State do
    defstruct ifname: nil,
              query_types: [],
              services: [],
              # Note: Erlang string
              dot_local_name: '',
              ttl: 3600,
              ip: {0, 0, 0, 0},
              udp: nil
  end

  ##############################################################################
  #   Public interface
  ##############################################################################
  def start({_ifname, _mdns_config} = opts) do
    GenServer.start(__MODULE__, opts)
  end

  @doc """
  Leave the mDNS group - close the UDP port. Stop this GenServer.
  """
  def stop_server(pid) do
    GenServer.call(pid, :leave_mdns_group)
    GenServer.stop(pid)
  end

  # TODO REMOVE ME
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  A convenience function for making mDNS queries.
  :a = Address Mapping
  """
  def query(pid, type = :a, domain) do
    GenServer.call(pid, {:query, type, domain})
  end

  ##############################################################################
  #   GenServer callbacks
  ##############################################################################
  @impl true
  def init({ifname, mdns_config}) do
    # A list of query types that we'll respond to.
    query_types = mdns_config.types
    # Construct a list of service names that we'll respond to
    services =
      Enum.map(
        mdns_config.services,
        fn service ->
          {"_#{service.protocol}._#{service.transport}", service.port, service.weight,
           service.priority}
        end
      )

    # We need the IP address for this network interface
    with {:ok, ip_tuple} <- ifname_to_ip(ifname) do
      discovery_name = resolve_mdns_name(mdns_config.service)
      dot_local_name = discovery_name <> "." <> mdns_config.domain
      # Join the mDNS multicast group
      {:ok, udp} = :gen_udp.open(@mdns_port, udp_options(ip_tuple))

      {:ok,
       %State{
         query_types: query_types,
         services: services,
         ifname: ifname,
         ip: ip_tuple,
         ttl: mdns_config.ttl,
         udp: udp,
         dot_local_name: to_charlist(dot_local_name)
       }}
    else
      {:error, reason} ->
        Logger.error("reason: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  @doc """
  Leave the mDNS UDP group.
  """
  def handle_call(:leave_mdns_group, _from, state) do
    if state.udp do
      :gen_udp.close(state.udp)
    end

    {:reply, :ok, %State{state | udp: nil}}
  end

  @doc """
  This handle_info() captures mDNS UDP multicast packets. Some client/service has
  written to the mDNS multicast port. We are only interested in queries and of
  those queries those that are germane.
  """
  @impl true
  def handle_info({:udp, _socket, _ip, _port, packet}, state) do
    # Decode the UDP packet
    dns_record = DNS.Record.decode(packet)
    # qr is the query/response flag; false (0) = query, true (1) = response
    if !dns_record.header.qr && length(dns_record.qdlist) > 0 do
      {:noreply, prepare_response(dns_record, state)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:no_replay, state}
  end

  ##############################################################################
  #   Private functions
  ##############################################################################
  defp prepare_response(dns_record, state) do
    Logger.info("DNS RECORD\n#{inspect(dns_record)}")
    # There can be multiple questions in a query. And it must be one of the
    # query types specified in the configuration
    dns_record.qdlist
    |> Enum.filter(fn q -> q.type in state.query_types end)
    |> Enum.each(fn %DNS.Query{} = query ->
      handle_query(query, dns_record, state)
    end)

    state
  end

  # An "A" type query. Address mapping record. Return the IP address if
  # this host name matches the query domain.
  defp handle_query(%DNS.Query{class: :in, type: :a, domain: domain} = _query, dns_record, state) do
    case state.dot_local_name == domain do
      true ->
        resource_record = %DNS.Resource{
          class: :in,
          type: :a,
          ttl: state.ttl,
          domain: state.dot_local_name,
          data: state.ip
        }

        send_response([resource_record], dns_record.qdlist, state)

      _ ->
        nil
    end
  end

  # A "PTR" type query. Reverse address lookup. Return the hostname of an
  # IP address
  defp handle_query(
         %DNS.Query{class: :in, type: :ptr, domain: domain} = _query,
         dns_record,
         state
       ) do
    # Convert our IP address so as to be able to match the arpa address
    # in the query.
    # Arpa address for IP 192.168.0.112 is 112.0.168.192,in-addr.arpa
    arpa_address =
      state.ip
      |> Tuple.to_list()
      |> Enum.reverse()
      |> Enum.join(".")

    # Only need to match the beginning characters
    if String.starts_with?(to_string(domain), arpa_address) do
      resource_record = %DNS.Resource{
        class: :in,
        type: :ptr,
        ttl: state.ttl,
        data: state.dot_local_name
      }

      send_response([resource_record], dns_record.qdlist, state)
    end
  end

  # A "SRV" type query. Find services, e.g., HTTP, SSH. The domain field in a
  # SRV service query will look like "_http._tcp". Respond only on an exact
  # match
  defp handle_query(
         %DNS.Query{class: :in, type: :srv, domain: domain} = _query,
         dns_record,
         state
       ) do
    state.services
    |> Enum.filter(fn {service, _port, _weight, _priority} -> to_string(domain) == service end)
    |> Enum.each(fn {service, port, weight, priority} ->
      # construct the data value to be returned
      # data = <<priority::size(16), weight::size(16), port::size(16)>>

      resource_record = %DNS.Resource{
        class: :in,
        type: :srv,
        ttl: state.ttl,
        data: ''
      }

      send_response([resource_record], dns_record.qdlist, state)
    end)
  end

  # Any other type of query, e.g., PTR, etc. should be handled individually.
  defp handle_query(%DNS.Query{type: type} = _query, _dns_record, _state) do
    Logger.info("IGNORING QUERY TYPE: #{inspect(type)}")
  end

  defp send_response([], _qdlist, _state), do: nil

  defp send_response(dns_resource_records, qdlist, state) do
    # Construct a DNS record from the list of services
    packet = %DNS.Record{@response_packet | :anlist => dns_resource_records, :qdlist => qdlist}
    Logger.info("DNS Response packet\n#{inspect(packet)}")
    dns_record = DNS.Record.encode(packet)
    :gen_udp.send(state.udp, @mdns_ip, @mdns_port, dns_record)
  end

  defp ifname_to_ip(ifname) do
    ifname_cl = to_charlist(ifname)

    with {:ok, ifaddrs} <- :inet.getifaddrs(),
         {_, params} <- Enum.find(ifaddrs, fn {k, _v} -> k == ifname_cl end),
         addr when is_tuple(addr) <- Keyword.get(params, :addr) do
      {:ok, addr}
    else
      _ ->
        {:error, :no_ip_address}
    end
  end

  defp resolve_mdns_name(nil), do: nil

  defp resolve_mdns_name(:hostname) do
    {:ok, hostname} = :inet.gethostname()
    to_dot_local_name(hostname)
  end

  defp resolve_mdns_name(mdns_name), do: mdns_name

  defp to_dot_local_name(name) do
    # Use the first part of the domain name and concatenate '.local'
    name
    |> to_string()
    |> String.split(".")
    |> hd()
  end

  defp udp_options(ip),
    do: [
      :binary,
      active: true,
      add_membership: {@mdns_ip, ip},
      multicast_if: ip,
      multicast_loop: true,
      multicast_ttl: 255,
      reuseaddr: true
    ]
end
