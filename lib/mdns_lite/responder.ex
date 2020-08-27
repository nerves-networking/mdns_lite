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
  alias MdnsLite.{Configuration, Query}

  # Reserved IANA ip address and port for mDNS
  @mdns_ipv4 {224, 0, 0, 251}
  @mdns_port 5353
  @sol_socket 0xFFFF
  @so_reuseport 0x0200
  @so_reuseaddr 0x0004

  defmodule State do
    @moduledoc false
    @type t() :: struct()
    defstruct services: [],
              # RFC 6763 nomenclature, aka hostname
              instance_name: "",
              # Note: Erlang string
              dot_local_name: '',
              dot_alias_name: '',
              ttl: 120,
              ip: {0, 0, 0, 0},
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
    via_name(address)
    |> GenServer.whereis()
    |> case do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  @spec refresh(:inet.ip_address() | pid(), any) :: :ok | {:error, :no_responder}
  def refresh(address_or_pid, data \\ [])

  def refresh(address, config) when is_tuple(address) do
    via_name(address)
    |> GenServer.whereis()
    |> refresh(config)
  end

  def refresh(pid, config) when is_pid(pid) do
    GenServer.call(pid, {:refresh, config})
  end

  def refresh(_, _), do: {:error, :no_responder}

  ##############################################################################
  #   GenServer callbacks
  ##############################################################################
  @impl true
  def init(address) do
    # Join the mDNS multicast group
    state =
      %State{ip: address, skip_udp: Application.get_env(:mdns_lite, :skip_udp)}
      |> add_config_values()

    {:ok, state, {:continue, :initialization}}
  end

  @impl true
  def handle_continue(:initialization, %{skip_udp: true} = state) do
    # Used only for testing.
    {:noreply, state}
  end

  def handle_continue(:initialization, state) do
    {:ok, udp} = :gen_udp.open(@mdns_port, udp_options(state.ip))

    {:noreply, %{state | udp: udp}}
  end

  @impl true
  def handle_call({:refresh, config}, _from, state) do
    {:reply, :ok, add_config_values(state, config)}
  end

  @doc """
  This handle_info() captures mDNS UDP multicast packets. Some client/service has
  written to the mDNS multicast port. We are only interested in queries and of
  those queries those that are germane.
  """
  @impl true
  def handle_info({:udp, _socket, src_ip, src_port, packet}, state) do
    # Decode the UDP packet
    with {:ok, dns_record} <- :inet_dns.decode(packet),
         dns = DNS.Record.from_record(dns_record),
         # qr is the query/response flag; false (0) = query, true (1) = response
         false <- dns.header.qr do
      # There can be multiple queries in each request
      dns.qdlist
      |> Enum.map(fn qd -> {qd.class, Query.handle(qd, state)} end)
      |> Enum.each(fn
        # Erlang doesn't know about unicast class
        {32769, resources} ->
          send_response(resources, dns, {src_ip, src_port}, state)

        {_, resources} ->
          send_response(resources, dns, mdns_destination(src_ip, src_port), state)
      end)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ##############################################################################
  #   Private functions
  ##############################################################################
  defp send_response([], _dns_record, _dest, _state), do: :ok

  defp send_response(dns_resource_records, dns_record, {dest_address, dest_port}, state) do
    # Construct an mDNS response from the query plus answers (resource records)
    packet = response_packet(dns_record.header.id, dns_resource_records)

    # _ = Logger.debug("Sending DNS response to #{inspect(dest_address)}/#{inspect(dest_port)}")
    # _ = Logger.debug("#{inspect(packet)}")

    dns_record = DNS.Record.encode(packet)
    :gen_udp.send(state.udp, dest_address, dest_port, dns_record)
  end

  # A standard mDNS response packet
  defp response_packet(id, answer_list),
    do: %DNS.Record{
      header: %DNS.Header{
        id: id,
        aa: true,
        qr: true,
        opcode: 0,
        rcode: 0
      },
      # Query list. Must be empty according to RFC 6762 Section 6.
      qdlist: [],
      # A list of answer entries. Can be empty.
      anlist: answer_list,
      # A list of resource entries. Can be empty.
      arlist: []
    }

  defp mdns_destination(_src_address, @mdns_port), do: {@mdns_ipv4, @mdns_port}

  defp mdns_destination(src_address, src_port) do
    # Legacy Unicast Response
    # See RFC 6762 6.7
    {src_address, src_port}
  end

  defp resolve_mdns_name(nil), do: nil

  defp resolve_mdns_name(:hostname) do
    {:ok, hostname} = :inet.gethostname()
    hostname |> to_string
  end

  defp resolve_mdns_name(mdns_name), do: mdns_name

  defp add_config_values(state, config \\ []) do
    config = if is_list(config), do: config, else: []
    mdns_config = Keyword.get_lazy(config, :mdns_config, &Configuration.get_mdns_config/0)
    mdns_services = Keyword.get_lazy(config, :mdns_services, &Configuration.get_mdns_services/0)
    instance_name = resolve_mdns_name(mdns_config[:host]) || state.host
    dot_local_name = "#{instance_name}.local"

    dot_alias_name =
      if mdns_config[:host_name_alias], do: "#{mdns_config.host_name_alias}.local", else: ""

    %{
      state
      | # A list of services with types that we'll match against
        services: mdns_services,
        ttl: mdns_config[:ttl] || state.ttl,
        instance_name: instance_name,
        dot_local_name: to_charlist(dot_local_name),
        dot_alias_name: to_charlist(dot_alias_name)
    }
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
    ] ++ reuse_port()
  end

  defp reuse_port() do
    case :os.type() do
      {:unix, :linux} ->
        reuse_port_linux()

      {:unix, os_name} when os_name in [:darwin, :freebsd, :openbsd, :netbsd] ->
        get_reuse_port()

      {:win32, _unused} ->
        get_reuse_address()

      _ ->
        []
    end
  end

  defp reuse_port_linux() do
    case :os.version() do
      {major, minor, _} when major > 3 or (major == 3 and minor >= 9) ->
        get_reuse_port()

      _before_3_9 ->
        get_reuse_address()
    end
  end

  defp get_reuse_port(), do: [{:raw, @sol_socket, @so_reuseport, <<1::native-32>>}]

  defp get_reuse_address(), do: [{:raw, @sol_socket, @so_reuseaddr, <<1::native-32>>}]
end
