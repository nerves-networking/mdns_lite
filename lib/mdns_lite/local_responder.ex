defmodule MdnsLite.LocalResponder do
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
  require Record
  alias MdnsLite.{TableServer, IfInfo}
  import MdnsLite.DNS

  @mdns_ipv4 {127, 0, 0, 1}
  @mdns_port 25353
  @sol_socket 0xFFFF
  @so_reuseport 0x0200
  @so_reuseaddr 0x0004

  ##############################################################################
  #   Public interface
  ##############################################################################
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(init_args) do
    GenServer.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  @doc """
  Send a query over mDNS
  """
  @spec query(DNS.dns_query()) :: {:ok, [DNS.dns_rr()]} | {:error, any()}
  def query(q) when Record.is_record(q, :dns_query) do
    GenServer.call(__MODULE__, {:query, q})
  end

  ##############################################################################
  #   GenServer callbacks
  ##############################################################################
  @impl GenServer
  def init(_opts) do
    if Application.get_env(:mdns_lite, :skip_udp) do
      :ignore
    else
      {:ok, udp} = :gen_udp.open(@mdns_port, udp_options())

      {:ok, %{udp: udp}}
    end
  end

  @impl GenServer
  def handle_call({:query, q}, from, state) do
    # Check our cache first
    # send query
    # set timeout/retry timer
    # check whether response has come in
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:udp, _socket, src_ip, src_port, packet}, state) do
    # Decode the UDP packet
    with {:ok, dns_record} <- :inet_dns.decode(packet),
         dns_rec(header: header, qdlist: qdlist) = dns_record,
         # qr is the query/response flag; false (0) = query, true (1) = response
         dns_header(qr: false) <- header do
      # only respond to the first query
      anlist = TableServer.lookup(hd(qdlist), %IfInfo{ipv4_address: {127, 0, 0, 1}})

      send_response(qdlist, anlist, dns_record, {src_ip, src_port}, state)
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
  defp send_response(
         qdlist,
         [],
         dns_rec(header: dns_header(id: id)),
         {dest_address, dest_port},
         state
       ) do
    IO.puts("Not found")

    packet =
      dns_rec(
        header: dns_header(id: id, qr: true, aa: false, rcode: 5),
        # Query list. Must be empty according to RFC 6762 Section 6.
        qdlist: qdlist,
        # A list of answer entries. Can be empty.
        anlist: [],
        # nslist Can be empty.
        nslist: [],
        # arlist A list of resource entries. Can be empty.
        arlist: []
      )

    dns_record = :inet_dns.encode(packet)
    :gen_udp.send(state.udp, dest_address, dest_port, dns_record)
  end

  defp send_response(
         qdlist,
         anlist,
         dns_rec(header: dns_header(id: id)),
         {dest_address, dest_port},
         state
       ) do
    IO.puts("Found it")

    packet =
      dns_rec(
        header: dns_header(id: id, qr: true, aa: true),
        # Query list. Must be empty according to RFC 6762 Section 6.
        qdlist: qdlist,
        # A list of answer entries. Can be empty.
        anlist: anlist,
        # nslist Can be empty.
        nslist: [],
        # arlist A list of resource entries. Can be empty.
        arlist: []
      )

    dns_record = :inet_dns.encode(packet)
    :gen_udp.send(state.udp, dest_address, dest_port, dns_record)
  end

  defp udp_options() do
    [
      :binary,
      active: true,
      ip: @mdns_ipv4,
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
