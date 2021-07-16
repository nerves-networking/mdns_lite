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
  alias MdnsLite.{IfInfo, TableServer}
  import MdnsLite.DNS

  # Reserved IANA ip address and port for mDNS
  @mdns_ipv4 {224, 0, 0, 251}
  @mdns_port 5353
  @sol_socket 0xFFFF
  @so_reuseport 0x0200
  @so_reuseaddr 0x0004

  defmodule State do
    @moduledoc false
    @type t() :: struct()
    defstruct ip: {0, 0, 0, 0},
              udp: nil,
              skip_udp: false
  end

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

  @doc """
  Leave the mDNS group - close the UDP port. Stop this GenServer.
  """
  @spec stop_server(:inet.ip_address()) :: :ok
  def stop_server(address) do
    GenServer.stop(via_name(address))
  end

  @spec refresh(:inet.ip_address(), any) :: :ok | {:error, :no_responder}
  def refresh(address, config) do
    GenServer.call(via_name(address), {:refresh, config})
  end

  ##############################################################################
  #   GenServer callbacks
  ##############################################################################
  @impl GenServer
  def init(address) do
    # Join the mDNS multicast group
    state = %State{ip: address, skip_udp: Application.get_env(:mdns_lite, :skip_udp)}

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

  @doc """
  This handle_info() captures mDNS UDP multicast packets. Some client/service has
  written to the mDNS multicast port. We are only interested in queries and of
  those queries those that are germane.
  """
  @impl GenServer
  def handle_info({:udp, _socket, src_ip, src_port, packet}, state) do
    # Decode the UDP packet
    with {:ok, dns_record} <- :inet_dns.decode(packet),
         dns_rec(header: header, qdlist: qdlist) = dns_record,
         # qr is the query/response flag; false (0) = query, true (1) = response
         dns_header(qr: false) <- header do
      # There can be multiple queries in each request
      qdlist
      |> Enum.map(fn dns_query(class: class) = qd ->
        {class, TableServer.lookup(qd, %IfInfo{ipv4_address: state.ip})}
      end)
      |> Enum.each(fn
        # Erlang doesn't know about unicast class
        {32769, resources} ->
          send_response(resources, dns_record, {src_ip, src_port}, state)

        {_, resources} ->
          send_response(resources, dns_record, mdns_destination(src_ip, src_port), state)
      end)
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ##############################################################################
  #   Private functions
  ##############################################################################
  defp send_response([], _dns_record, _dest, _state), do: :ok

  defp send_response(
         dns_resource_records,
         dns_rec(header: dns_header(id: id)),
         {dest_address, dest_port},
         state
       ) do
    # Construct an mDNS response from the query plus answers (resource records)
    packet = response_packet(id, dns_resource_records)

    # _ = Logger.debug("Sending DNS response to #{inspect(dest_address)}/#{inspect(dest_port)}")
    # _ = Logger.debug("#{inspect(packet)}")

    dns_record = :inet_dns.encode(packet)
    :gen_udp.send(state.udp, dest_address, dest_port, dns_record)
  end

  # A standard mDNS response packet
  defp response_packet(id, answer_list),
    do:
      dns_rec(
        # AA (Authoritative Answer) bit MUST be true - RFC 6762 18.4
        header: dns_header(id: id, qr: true, aa: true),
        # Query list. Must be empty according to RFC 6762 Section 6.
        qdlist: [],
        # A list of answer entries. Can be empty.
        anlist: answer_list,
        # nslist Can be empty.
        nslist: [],
        # arlist A list of resource entries. Can be empty.
        arlist: []
      )

  defp mdns_destination(_src_address, @mdns_port), do: {@mdns_ipv4, @mdns_port}

  defp mdns_destination(src_address, src_port) do
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
