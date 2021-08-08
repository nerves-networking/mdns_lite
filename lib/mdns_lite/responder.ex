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
  require Logger
  alias MdnsLite.{Cache, IfInfo, TableServer}
  import MdnsLite.DNS

  # Reserved IANA ip address and port for mDNS
  @mdns_ipv4 {224, 0, 0, 251}
  @mdns_port 5353
  @sol_socket 0xFFFF
  @so_reuseport 0x0200
  @so_reuseaddr 0x0004

  defstruct ip: {0, 0, 0, 0},
            cache: Cache.new(),
            udp: nil,
            skip_udp: false

  @type state() :: %{
          ip: :inet.ip_address(),
          cache: Cache.t(),
          udp: :gen_udp.socket(),
          skip_udp: boolean()
        }

  ##############################################################################
  #   Public interface
  ##############################################################################
  @spec start_link(:inet.ip_address()) :: GenServer.on_start()
  def start_link(address) do
    GenServer.start_link(__MODULE__, address, name: via_name(address))
  end

  defp via_name(address) do
    {:via, Registry, {MdnsLite.ResponderRegistry, address}}
  end

  @spec get_all_caches() :: [{:inet.ip_address(), Cache.t()}]
  def get_all_caches() do
    Registry.lookup(MdnsLite.Responders, __MODULE__)
    |> Enum.map(fn {pid, ip_address} -> {ip_address, get_cache(pid)} end)
  end

  @spec get_cache(GenServer.server()) :: Cache.t()
  def get_cache(server) do
    GenServer.call(server, :get_cache)
  end

  @doc """
  Leave the mDNS group - close the UDP port. Stop this GenServer.
  """
  @spec stop_server(:inet.ip_address()) :: :ok
  def stop_server(address) do
    GenServer.stop(via_name(address))
  end

  ##############################################################################
  #   GenServer callbacks
  ##############################################################################
  @impl GenServer
  def init(address) do
    # Join the mDNS multicast group
    state = %__MODULE__{ip: address, skip_udp: Application.get_env(:mdns_lite, :skip_udp)}
    {:ok, _} = Registry.register(MdnsLite.Responders, __MODULE__, address)

    {:ok, state, {:continue, :initialization}}
  end

  @impl GenServer
  def handle_continue(:initialization, %{skip_udp: true} = state) do
    # Used only for testing.
    {:noreply, state}
  end

  def handle_continue(:initialization, state) do
    {:ok, udp} = :gen_udp.open(@mdns_port, udp_options(state.ip))

    {:noreply, %{state | udp: udp}}
  end

  @impl GenServer
  def handle_call(:get_cache, _from, state) do
    {:reply, state.cache, state}
  end

  @impl GenServer
  def handle_info({:udp, _socket, src_ip, src_port, packet}, state) do
    new_state =
      case :inet_dns.decode(packet) do
        {:ok, msg} -> handle_msg({src_ip, src_port}, msg, state)
        _ -> state
      end

    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.info("Responder ignoring #{inspect(msg)}")
    {:noreply, state}
  end

  ##############################################################################
  #   Private functions
  ##############################################################################
  defp handle_msg(
         src,
         dns_rec(header: dns_header(qr: false), qdlist: qdlist) = msg,
         state
       ) do
    # mDNS request message
    qdlist
    |> Enum.map(fn dns_query(class: class) = qd ->
      {class, TableServer.lookup(qd, %IfInfo{ipv4_address: state.ip})}
    end)
    |> Enum.each(fn
      # Erlang doesn't know about unicast class
      {32769, result} -> send_response(result, msg, src, state)
      {_, result} -> send_response(result, msg, mdns_destination(src), state)
    end)

    # If the request had any entries, cache them
    update_cache(msg, state)
  end

  defp handle_msg(_src, dns_rec(header: dns_header(qr: true)) = msg, state) do
    # A response message or update so cache whatever it contains
    update_cache(msg, state)
  end

  defp update_cache(dns_rec(anlist: anlist, arlist: arlist), state) do
    now = System.monotonic_time(:second)
    new_cache = state.cache |> Cache.insert_many(now, anlist) |> Cache.insert_many(now, arlist)
    %{state | cache: new_cache}
  end

  defp send_response(%{answer: []}, _dns_record, _dest, _state), do: :ok

  defp send_response(
         result,
         dns_rec(header: dns_header(id: id)),
         {dest_address, dest_port},
         state
       ) do
    # Construct an mDNS response from the query plus answers (resource records)
    packet = response_packet(id, result)

    # _ = Logger.debug("Sending DNS response to #{inspect(dest_address)}/#{inspect(dest_port)}")
    # _ = Logger.debug("#{inspect(packet)}")

    dns_record = :inet_dns.encode(packet)
    :gen_udp.send(state.udp, dest_address, dest_port, dns_record)
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

  defp mdns_destination({_src_address, @mdns_port}), do: {@mdns_ipv4, @mdns_port}

  defp mdns_destination({src_address, src_port}) do
    # Legacy Unicast Response
    # See RFC 6762 6.7
    {src_address, src_port}
  end

  defp udp_options(ip) do
    [
      :binary,
      active: true,
      add_membership: {@mdns_ipv4, ip},
      multicast_if: ip,
      multicast_loop: true,

      # IP TTL should be 255. See https://tools.ietf.org/html/rfc6762#section-11
      multicast_ttl: 255,
      reuseaddr: true
    ] ++ reuse_port(:os.type())
  end

  defp reuse_port({:unix, :linux}) do
    case :os.version() do
      {major, minor, _} when major > 3 or (major == 3 and minor >= 9) ->
        get_reuse_port()

      _before_3_9 ->
        get_reuse_address()
    end
  end

  defp reuse_port({:unix, os_name}) when os_name in [:darwin, :freebsd, :openbsd, :netbsd] do
    get_reuse_port()
  end

  defp reuse_port({:win32, _}) do
    get_reuse_address()
  end

  defp reuse_port(_), do: []

  defp get_reuse_port(), do: [{:raw, @sol_socket, @so_reuseport, <<1::native-32>>}]

  defp get_reuse_address(), do: [{:raw, @sol_socket, @so_reuseaddr, <<1::native-32>>}]
end
