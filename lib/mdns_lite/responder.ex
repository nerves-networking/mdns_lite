defmodule MdnsLite.Responder do
  @moduledoc false

  # A GenServer that is responsible for responding to a limited number of mDNS
  # requests (queries). A UDP port is opened on the mDNS reserved IP/port. Any
  # UDP packets will be caught by handle_info() but only a subset of them are
  # of interest. The module `MdnsLite.Query does the actual query parsing.
  #
  # This module is started and stopped dynamically by MdnsLite.ResponderSupervisor
  #
  # There is one of these servers for every network interface managed by
  # MdnsLite.

  use GenServer
  import MdnsLite.DNS
  alias MdnsLite.{Cache, DNS, IfInfo, TableServer}
  require Logger

  # Reserved IANA ip address and port for mDNS
  @mdns_ipv4 {224, 0, 0, 251}
  @mdns_port 5353

  defstruct ifname: nil,
            ip: {0, 0, 0, 0},
            cache: Cache.new(),
            udp: nil,
            select_handle: nil,
            skip_udp: false

  @type state() :: %{
          ifname: String.t(),
          ip: :inet.ip_address(),
          cache: Cache.t(),
          udp: :socket.socket(),
          skip_udp: boolean()
        }

  ##############################################################################
  #   Public interface
  ##############################################################################
  @spec start_link({String.t(), :inet.ip_address()}) :: GenServer.on_start()
  def start_link(ifname_address) do
    GenServer.start_link(__MODULE__, ifname_address, name: via_name(ifname_address))
  end

  defp via_name(ifname_address) do
    {:via, Registry, {MdnsLite.ResponderRegistry, ifname_address}}
  end

  @spec get_all_caches() :: [%{ifname: String.t(), ip: :inet.ip_address(), cache: Cache.t()}]
  def get_all_caches() do
    Registry.lookup(MdnsLite.Responders, __MODULE__)
    |> Enum.map(fn {pid, {ifname, ip_address}} ->
      %{ifname: ifname, ip: ip_address, cache: get_cache(pid)}
    end)
  end

  @spec get_cache(GenServer.server()) :: Cache.t()
  def get_cache(server) do
    GenServer.call(server, :get_cache)
  end

  @spec query_all_caches(DNS.dns_query()) :: %{answer: [DNS.dns_rr()], additional: [DNS.dns_rr()]}
  def query_all_caches(q) do
    Registry.lookup(MdnsLite.Responders, __MODULE__)
    |> Enum.reduce(%{answer: [], additional: []}, fn {pid, _}, acc ->
      MdnsLite.Table.merge_results(acc, query_cache(pid, q))
    end)
  end

  @spec query_cache(GenServer.server(), DNS.dns_query()) :: %{
          answer: [DNS.dns_rr()],
          additional: [DNS.dns_rr()]
        }
  def query_cache(server, q) do
    GenServer.call(server, {:query_cache, q})
  end

  @spec multicast_all(DNS.dns_query()) :: :ok
  def multicast_all(q) do
    Registry.lookup(MdnsLite.Responders, __MODULE__)
    |> Enum.each(fn {pid, _} -> multicast(pid, q) end)
  end

  @spec multicast(GenServer.server(), DNS.dns_query()) :: :ok
  def multicast(server, q) do
    GenServer.cast(server, {:multicast, q})
  end

  @doc """
  Leave the mDNS group - close the UDP port. Stop this GenServer.
  """
  @spec stop_server(String.t(), :inet.ip_address()) :: :ok
  def stop_server(ifname, address) do
    GenServer.stop(via_name({ifname, address}))
  end

  ##############################################################################
  #   GenServer callbacks
  ##############################################################################
  @impl GenServer
  def init({ifname, address}) do
    # Join the mDNS multicast group
    state = %__MODULE__{
      ifname: ifname,
      ip: address,
      skip_udp: Application.get_env(:mdns_lite, :skip_udp)
    }

    {:ok, _} = Registry.register(MdnsLite.Responders, __MODULE__, {ifname, address})

    {:ok, state, {:continue, :initialization}}
  end

  @impl GenServer
  def handle_continue(:initialization, %{skip_udp: true} = state) do
    # Used only for testing.
    {:noreply, state}
  end

  def handle_continue(:initialization, state) do
    {:ok, udp} = :socket.open(:inet, :dgram, :udp)

    :ok = bindtodevice(udp, state.ifname)
    :ok = :socket.setopt(udp, :socket, :reuseport, true)
    :ok = :socket.setopt(udp, :socket, :reuseaddr, true)
    :ok = :socket.setopt(udp, :ip, :multicast_loop, false)
    # IP TTL should be 255. See https://tools.ietf.org/html/rfc6762#section-11
    :ok = :socket.setopt(udp, :ip, :multicast_ttl, 255)
    :ok = :socket.setopt(udp, :ip, :multicast_if, state.ip)
    :ok = :socket.bind(udp, %{family: :inet, port: @mdns_port})

    :ok = :socket.setopt(udp, :ip, :add_membership, %{multiaddr: @mdns_ipv4, interface: state.ip})

    new_state = %{state | udp: udp} |> process_receives()
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call(:get_cache, _from, state) do
    new_state = gc_cache(state)
    {:reply, new_state.cache, new_state}
  end

  def handle_call({:query_cache, q}, _from, state) do
    new_state = gc_cache(state)
    {:reply, Cache.query(new_state.cache, q), new_state}
  end

  @impl GenServer
  def handle_cast({:multicast, q}, state) do
    message = dns_rec(header: dns_header(id: 0, qr: false, aa: false), qdlist: [q])
    data = DNS.encode(message)
    dest = %{family: :inet, port: @mdns_port, addr: @mdns_ipv4}

    if state.udp do
      case :socket.sendto(state.udp, data, dest) do
        {:error, reason} ->
          Logger.warn("mdns_lite multicast send failed: #{inspect(reason)}")

        :ok ->
          :ok
      end
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        {:"$socket", udp, :select, select_handle},
        %{udp: udp, select_handle: select_handle} = state
      ) do
    {:noreply, process_receives(state)}
  end

  def handle_info(msg, state) do
    Logger.error("mdns_lite responder ignoring #{inspect(msg)}, #{inspect(state)}")
    {:noreply, state}
  end

  ##############################################################################
  #   Private functions
  ##############################################################################
  defp process_receives(state) do
    case :socket.recvfrom(state.udp, [], :nowait) do
      {:ok, {source, data}} ->
        state
        |> process_packet(source, data)
        |> process_receives()

      {:select, {:select_info, _tag, select_handle}} ->
        %{state | select_handle: select_handle}
    end
  end

  defp process_packet(state, source, data) do
    case DNS.decode(data) do
      {:ok, msg} -> process_dns(state, source, msg)
      _ -> state
    end
  end

  defp process_dns(
         state,
         source,
         dns_rec(header: dns_header(qr: false), qdlist: qdlist) = msg
       ) do
    # mDNS request message
    Enum.each(qdlist, &run_query(&1, msg, source, state))

    # If the request had any entries, cache them
    update_cache(msg, state)
  end

  defp process_dns(state, _source, dns_rec(header: dns_header(qr: true)) = msg) do
    # A response message or update so cache whatever it contains
    update_cache(msg, state)
  end

  defp update_cache(dns_rec(anlist: anlist, arlist: arlist), state) do
    now = System.monotonic_time(:second)
    new_cache = state.cache |> Cache.insert_many(now, anlist) |> Cache.insert_many(now, arlist)
    %{state | cache: new_cache}
  end

  defp run_query(dns_query(unicast_response: unicast) = qd, msg, source, state) do
    result = TableServer.query(qd, %IfInfo{ipv4_address: state.ip})

    if unicast do
      send_response(result, msg, source, state)
    else
      send_response(result, msg, mdns_destination(source), state)
    end
  end

  defp send_response(%{answer: []}, _dns_record, _dest, _state), do: :ok

  defp send_response(
         result,
         dns_rec(header: dns_header(id: id)),
         dest,
         state
       ) do
    # Construct an mDNS response from the query plus answers (resource records)
    packet = response_packet(id, result)

    # _ = Logger.debug("Sending DNS response to #{inspect(dest_address)}/#{inspect(dest_port)}")
    # _ = Logger.debug("#{inspect(packet)}")

    data = DNS.encode(packet)
    _ = :socket.sendto(state.udp, data, dest)
    :ok
  end

  # A standard mDNS response packet
  defp response_packet(id, result),
    do:
      dns_rec(
        # AA (Authoritative Answer) bit MUST be true - RFC 6762 18.4
        header: dns_header(id: id, qr: true, aa: true),
        # Query list. Must be empty according to RFC 6762 Section 6.
        qdlist: [],
        # A list of answer entries. Can be empty.
        anlist: result.answer,
        # nslist Can be empty.
        nslist: [],
        # arlist A list of resource entries. Can be empty.
        arlist: result.additional
      )

  defp mdns_destination(%{family: :inet, port: @mdns_port}),
    do: %{family: :inet, port: @mdns_port, addr: @mdns_ipv4}

  defp mdns_destination(%{family: :inet} = source) do
    # Legacy Unicast Response
    # See RFC 6762 6.7
    source
  end

  defp gc_cache(state) do
    %{state | cache: Cache.gc(state.cache, System.monotonic_time(:second))}
  end

  defp bindtodevice(socket, ifname) do
    case :os.type() do
      {:unix, :linux} ->
        :socket.setopt(socket, :socket, :bindtodevice, String.to_charlist(ifname))

      {:unix, :darwin} ->
        # TODO!
        :ok
    end
  end
end
