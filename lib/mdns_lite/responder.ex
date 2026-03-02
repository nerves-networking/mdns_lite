# SPDX-FileCopyrightText: 2019 Frank Hunleth
# SPDX-FileCopyrightText: 2019 Jon Carstens
# SPDX-FileCopyrightText: 2019 Peter C. Marks
# SPDX-FileCopyrightText: 2020 Eduardo Cunha
# SPDX-FileCopyrightText: 2021 Connor Rigby
# SPDX-FileCopyrightText: 2021 Peter Madsen-mygdal
# SPDX-FileCopyrightText: 2023 Ben Youngblood
# SPDX-FileCopyrightText: 2024 Michael Neumann
#
# SPDX-License-Identifier: Apache-2.0
#
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

  use GenServer, restart: :transient

  import MdnsLite.DNS

  alias MdnsLite.Cache
  alias MdnsLite.DNS
  alias MdnsLite.IfInfo
  alias MdnsLite.KnownAnswer
  alias MdnsLite.Options
  alias MdnsLite.Probe
  alias MdnsLite.TableServer
  alias MdnsLite.Utilities

  require Logger

  # Reserved IANA ip address and port for mDNS
  @mdns_ipv4 {224, 0, 0, 251}
  @mdns_ipv6 {0xFF02, 0, 0, 0, 0, 0, 0, 0xFB}
  @mdns_port 5353

  @type state() :: %{
          ifname: String.t(),
          ip: :inet.ip_address(),
          cache: Cache.t(),
          udp: :socket.socket(),
          select_handle: :socket.select_handle(),
          skip_udp: boolean(),
          probe: Probe.t() | nil,
          probe_timer: reference() | nil
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
  catch
    :exit, {:noproc, _} ->
      # Ignore if the server already stopped. It already exited due to the
      # network going down.
      :ok
  end

  ##############################################################################
  #   GenServer callbacks
  ##############################################################################
  @impl GenServer
  def init({ifname, address}) do
    # Join the mDNS multicast group
    state = %{
      ifname: ifname,
      ip: address,
      family: Utilities.ip_family(address),
      cache: Cache.new(),
      udp: nil,
      select_handle: nil,
      skip_udp: Application.get_env(:mdns_lite, :skip_udp),
      probe: nil,
      probe_timer: nil,
      pending_responses: %{},
      tc_pending: %{}
    }

    {:ok, _} = Registry.register(MdnsLite.Responders, __MODULE__, {ifname, address})

    {:ok, state, {:continue, :initialization}}
  end

  @impl GenServer
  def handle_continue(:initialization, %{skip_udp: true} = state) do
    # Used only for testing.
    {:noreply, state}
  end

  def handle_continue(:initialization, %{family: family} = state) do
    Logger.info("mdns_lite #{state.ifname}/#{inspect(state.ip)}")

    option_level =
      case family do
        :inet -> :ip
        :inet6 -> :ipv6
      end

    with {:ok, udp} <- :socket.open(family, :dgram, :udp),
         :ok <- bindtodevice(udp, state.ifname),
         :ok <- :socket.setopt(udp, :socket, :reuseport, true),
         :ok <- :socket.setopt(udp, :socket, :reuseaddr, true),
         :ok <- :socket.setopt(udp, option_level, :multicast_loop, false),
         :ok <- set_multicast_ttl(udp, state),
         {:ok, interface} <- get_interface_opt(state),
         :ok <- :socket.setopt(udp, option_level, :multicast_if, interface),
         :ok <- :socket.bind(udp, %{family: family, port: @mdns_port}),
         :ok <- add_membership(udp, interface, family) do
      new_state = %{state | udp: udp} |> start_probing() |> process_receives()
      {:noreply, new_state}
    else
      {:error, reason} ->
        Logger.error("mdns_lite #{state.ifname}/#{inspect(state.ip)} failed: #{inspect(reason)}")

        # Not being able to setup the socket is fatal since it means that the
        # interface went away or its IP address changed.
        {:stop, :normal, state}
    end
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
    dest = %{family: state.family, port: @mdns_port, addr: multicast_ip(state.family)}

    if state.udp do
      case :socket.sendto(state.udp, data, dest) do
        {:error, reason} ->
          Logger.warning("mdns_lite multicast send failed: #{inspect(reason)}")

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

  def handle_info(:probe_timer, state) do
    if state.probe do
      {new_probe, actions} = Probe.timer_fired(state.probe)
      new_state = %{state | probe: new_probe, probe_timer: nil}
      {:noreply, dispatch_actions(new_state, actions)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:delayed_response, dest_key}, state) do
    case Map.pop(state.pending_responses, dest_key) do
      {nil, _} ->
        {:noreply, state}

      {{result, msg}, new_pending} ->
        new_state = %{state | pending_responses: new_pending}
        send_response(result, msg, dest_key, new_state)
        {:noreply, new_state}
    end
  end

  def handle_info({:tc_timeout, source_key, msg}, state) do
    case Map.pop(state.tc_pending, source_key) do
      {nil, _} ->
        {:noreply, state}

      {{accumulated_answers, _timer}, new_tc_pending} ->
        # Process with accumulated known-answers
        new_state = %{state | tc_pending: new_tc_pending}
        msg_with_answers = dns_rec(msg, anlist: accumulated_answers)
        source = source_key
        new_state = process_dns_query(new_state, source, msg_with_answers)
        {:noreply, new_state}
    end
  end

  def handle_info({:records_removed, records}, state) do
    send_goodbye(records, state)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.error("mdns_lite responder ignoring #{inspect(msg)}, #{inspect(state)}")
    {:noreply, state}
  end

  ##############################################################################
  #   Private functions
  ##############################################################################

  # Probing and announcing

  defp start_probing(state) do
    options = TableServer.options()
    hostname = hd(options.hosts)
    records = TableServer.get_records()
    if_info = if_info_from_state(state)

    # Resolve interface-specific placeholders in records
    resolved_records =
      records
      |> Enum.flat_map(&resolve_record(&1, if_info))
      # Only probe unique (non-shared) records - skip PTR records
      |> Enum.filter(fn dns_rr(type: t) -> t != :ptr end)

    {probe, actions} = Probe.new(hostname, resolved_records)
    new_state = %{state | probe: probe}
    dispatch_actions(new_state, actions)
  end

  defp resolve_record(dns_rr(class: :in, type: :a, data: :ipv4_address), %{ipv4_address: nil}) do
    []
  end

  defp resolve_record(dns_rr(class: :in, type: :a, data: :ipv4_address) = rr, if_info) do
    [dns_rr(rr, data: if_info.ipv4_address)]
  end

  defp resolve_record(dns_rr(class: :in, type: :aaaa, data: :ipv6_address) = rr, if_info) do
    for address <- if_info.ipv6_addresses do
      dns_rr(rr, data: address)
    end
  end

  defp resolve_record(dns_rr(domain: :ipv4_arpa_address), _if_info), do: []
  defp resolve_record(dns_rr(domain: :ipv6_arpa_address), _if_info), do: []
  defp resolve_record(rr, _if_info), do: [rr]

  defp if_info_from_state(%{family: :inet, ip: ip}), do: %IfInfo{ipv4_address: ip}
  defp if_info_from_state(%{family: :inet6, ip: ip}), do: %IfInfo{ipv6_addresses: [ip]}

  defp dispatch_actions(state, actions) do
    Enum.reduce(actions, state, &dispatch_action/2)
  end

  defp dispatch_action({:send_probe, packet}, state) do
    send_packet(packet, state)
    state
  end

  defp dispatch_action({:send_announcement, packet}, state) do
    send_packet(packet, state)
    state
  end

  defp dispatch_action({:schedule_timer, ms}, state) do
    _ = state.probe_timer && Process.cancel_timer(state.probe_timer)
    timer = Process.send_after(self(), :probe_timer, ms)
    %{state | probe_timer: timer}
  end

  defp dispatch_action({:rename, new_hostname}, state) do
    Logger.info("mdns_lite: conflict detected, renaming to #{new_hostname}")
    TableServer.update_options(&Options.set_hosts(&1, [new_hostname | tl(&1.hosts)]))
    # Get fresh records after rename and update probe
    new_state = %{state | probe: nil, probe_timer: nil}
    start_probing(new_state)
  end

  defp dispatch_action(:complete, state) do
    Logger.debug("mdns_lite: probing complete for #{state.probe.hostname}")
    state
  end

  defp send_packet(packet, state) do
    if state.udp do
      data = DNS.encode(packet)
      dest = %{family: state.family, port: @mdns_port, addr: multicast_ip(state.family)}

      case :socket.sendto(state.udp, data, dest) do
        {:error, reason} ->
          Logger.warning("mdns_lite probe/announce send failed: #{inspect(reason)}")

        :ok ->
          :ok
      end
    end
  end

  # Packet processing

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
         dns_rec(header: dns_header(qr: false, tc: true), anlist: anlist) = msg
       ) do
    # TC (truncated) bit set - accumulate known-answers and wait for follow-up
    source_key = source_key(source)

    {existing_answers, _timer} =
      Map.get(state.tc_pending, source_key, {[], nil})

    accumulated = existing_answers ++ anlist
    timer = Process.send_after(self(), {:tc_timeout, source_key, msg}, 500)
    %{state | tc_pending: Map.put(state.tc_pending, source_key, {accumulated, timer})}
  end

  defp process_dns(
         state,
         source,
         dns_rec(header: dns_header(qr: false), anlist: anlist) = msg
       ) do
    # Check for accumulated TC known-answers from previous truncated queries
    source_key = source_key(source)

    {msg, state} =
      case Map.pop(state.tc_pending, source_key) do
        {nil, _} ->
          {msg, state}

        {{accumulated_answers, timer}, new_tc_pending} ->
          _ = timer && Process.cancel_timer(timer)
          combined = accumulated_answers ++ anlist
          {dns_rec(msg, anlist: combined), %{state | tc_pending: new_tc_pending}}
      end

    process_dns_query(state, source, msg)
  end

  defp process_dns(state, _source, dns_rec(header: dns_header(qr: true), anlist: anlist) = msg) do
    # A response message - check for conflicts with our probed names
    state = maybe_handle_conflict(state, anlist)

    # Cache whatever it contains
    update_cache(msg, state)
  end

  # TODO: Responding to queries over IPv6 is not supported yet
  defp process_dns_query(%{family: :inet6} = state, _source, msg) do
    update_cache(msg, state)
  end

  defp process_dns_query(state, source, dns_rec(qdlist: qdlist, nslist: nslist) = msg) do
    state = maybe_handle_simultaneous_probe(state, nslist)

    # Aggregate results for all questions into a single response
    empty = %{answer: [], additional: []}

    {unicast_result, multicast_result, has_shared} =
      Enum.reduce(qdlist, {empty, empty, false}, &aggregate_query(&1, &2, state))

    # Apply known-answer suppression (RFC 6762 §7.1) to multicast results
    known_answers = dns_rec(msg, :anlist)

    multicast_result = %{
      multicast_result
      | answer: KnownAnswer.suppress(multicast_result.answer, known_answers)
    }

    # Send unicast response immediately (with cache-flush stripped)
    if unicast_result.answer != [] do
      send_response(strip_cache_flush(unicast_result), msg, source, state)
    end

    # Send multicast response (with delay for shared records)
    state =
      if multicast_result.answer != [] do
        dest = mdns_destination(source)

        if has_shared do
          schedule_delayed_response(multicast_result, msg, dest, state)
        else
          send_response(multicast_result, msg, dest, state)
          state
        end
      else
        state
      end

    update_cache(msg, state)
  end

  defp aggregate_query(qd, {uni_acc, multi_acc, shared}, state) do
    domain = dns_query(qd, :domain)

    if state.probe && Probe.probing_name?(state.probe, domain) do
      {uni_acc, multi_acc, shared}
    else
      result = TableServer.query(qd, if_info_from_state(state))

      if dns_query(qd, :unicast_response) do
        {MdnsLite.Table.merge_results(uni_acc, result), multi_acc, shared}
      else
        is_shared = dns_query(qd, :type) == :ptr
        {uni_acc, MdnsLite.Table.merge_results(multi_acc, result), shared or is_shared}
      end
    end
  end

  defp source_key(source), do: source

  defp maybe_handle_simultaneous_probe(state, nslist) when is_list(nslist) and nslist != [] do
    if state.probe && state.probe.phase == :probing do
      # Check if any authority records conflict with our probed names
      conflicting =
        Enum.any?(nslist, fn rr ->
          Probe.probing_name?(state.probe, dns_rr(rr, :domain))
        end)

      if conflicting do
        {new_probe, actions} = Probe.simultaneous_probe_received(state.probe, nslist)
        new_state = %{state | probe: new_probe}
        dispatch_actions(new_state, actions)
      else
        state
      end
    else
      state
    end
  end

  defp maybe_handle_simultaneous_probe(state, _nslist), do: state

  defp maybe_handle_conflict(state, anlist) when is_list(anlist) and anlist != [] do
    if state.probe && state.probe.phase in [:probing, :announcing] do
      conflicting =
        Enum.any?(anlist, fn rr ->
          Probe.probing_name?(state.probe, dns_rr(rr, :domain))
        end)

      if conflicting do
        {new_probe, actions} = Probe.conflict_detected(state.probe)
        new_state = %{state | probe: new_probe}
        dispatch_actions(new_state, actions)
      else
        state
      end
    else
      state
    end
  end

  defp maybe_handle_conflict(state, _anlist), do: state

  defp update_cache(dns_rec(anlist: anlist, arlist: arlist), state) do
    now = System.monotonic_time(:second)
    new_cache = state.cache |> Cache.insert_many(now, anlist) |> Cache.insert_many(now, arlist)
    %{state | cache: new_cache}
  end

  defp strip_cache_flush(%{answer: answer, additional: additional}) do
    %{
      answer: Enum.map(answer, &dns_rr(&1, func: false)),
      additional: Enum.map(additional, &dns_rr(&1, func: false))
    }
  end

  defp schedule_delayed_response(result, dns_rec() = msg, dest, state) do
    case Map.get(state.pending_responses, dest) do
      nil ->
        # No pending response for this dest - schedule a new one
        delay = 20 + :rand.uniform(105)
        Process.send_after(self(), {:delayed_response, dest}, delay)
        new_pending = Map.put(state.pending_responses, dest, {result, msg})
        %{state | pending_responses: new_pending}

      {existing_result, existing_msg} ->
        # Merge with existing pending response (aggregation per II.15)
        merged = MdnsLite.Table.merge_results(existing_result, result)
        new_pending = Map.put(state.pending_responses, dest, {merged, existing_msg})
        %{state | pending_responses: new_pending}
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

  # Goodbye packets - send records with TTL=0 when they're removed
  defp send_goodbye(records, state) do
    goodbye_records = Enum.map(records, &dns_rr(&1, ttl: 0))

    packet =
      dns_rec(
        header: dns_header(id: 0, qr: true, aa: true),
        anlist: goodbye_records
      )

    send_packet(packet, state)
  end

  defp mdns_destination(%{family: :inet, port: @mdns_port}),
    do: %{family: :inet, port: @mdns_port, addr: @mdns_ipv4}

  defp mdns_destination(%{family: :inet6, port: @mdns_port}),
    do: %{family: :inet6, port: @mdns_port, addr: @mdns_ipv6}

  defp mdns_destination(%{family: family} = source) when family in [:inet, :inet6] do
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

      {:unix, _} ->
        # TODO!
        :ok
    end
  end

  # No difference between Linux and macOS for IPv6
  defp add_membership(udp, interface, :inet) do
    :socket.setopt(udp, :ip, :add_membership, %{
      multiaddr: multicast_ip(:inet),
      interface: interface
    })
  end

  @ipv6_option_join_group 12
  defp add_membership(udp, interface, :inet6) do
    case :os.type() do
      {:unix, :linux} ->
        :socket.setopt(udp, :ipv6, :add_membership, %{
          multiaddr: multicast_ip(:inet6),
          interface: interface
        })

      {:unix, :darwin} ->
        addr_bin =
          for int <- Tuple.to_list(@mdns_ipv6), into: <<>> do
            <<int::16>>
          end

        # This is a bit of a hack. See https://stackoverflow.com/a/38386150
        :socket.setopt_native(
          udp,
          {:ipv6, @ipv6_option_join_group},
          addr_bin <> <<interface::64>>
        )

      {:unix, _} ->
        # TODO!
        :ok
    end
  end

  # setopt uses the interface address for IPv4 and the interface index for IPv6
  defp get_interface_opt(%{family: :inet, ip: ip}), do: {:ok, ip}

  defp get_interface_opt(%{family: :inet6, ifname: ifname}) do
    ifname |> String.to_charlist() |> :net.if_name2index()
  end

  # IP TTL should be 255. See https://tools.ietf.org/html/rfc6762#section-11
  defp set_multicast_ttl(sock, %{family: :inet}),
    do: :socket.setopt(sock, :ip, :multicast_ttl, 255)

  defp set_multicast_ttl(sock, %{family: :inet6}),
    do: :socket.setopt(sock, :ipv6, :multicast_hops, 255)

  defp multicast_ip(:inet), do: @mdns_ipv4
  defp multicast_ip(:inet6), do: @mdns_ipv6
end
