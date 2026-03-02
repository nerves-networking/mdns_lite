# SPDX-FileCopyrightText: 2026 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule MdnsLite.Probe do
  @moduledoc false

  # Pure functional state machine for mDNS probing and announcing per RFC 6762 §8.
  #
  # States: :probing → :announcing → :running
  #
  # This module has no side effects - it returns actions that the caller
  # (Responder) dispatches. This makes it fully testable without GenServers or UDP.

  import MdnsLite.DNS

  alias MdnsLite.DNS

  @probe_interval 250
  @probe_count 3
  @announce_count 8
  @initial_announce_interval 1000
  @conflict_rate_limit_delay 5000
  @max_conflicts_before_rate_limit 15

  @type phase :: :probing | :announcing | :running

  @type action ::
          {:send_probe, DNS.dns_rec()}
          | {:send_announcement, DNS.dns_rec()}
          | {:schedule_timer, non_neg_integer()}
          | {:rename, String.t()}
          | :complete

  @type t :: %__MODULE__{
          phase: phase(),
          probe_count: non_neg_integer(),
          announce_count: non_neg_integer(),
          announce_interval: pos_integer(),
          conflict_count: non_neg_integer(),
          hostname: String.t(),
          original_hostname: String.t(),
          records: [DNS.dns_rr()]
        }

  defstruct phase: :probing,
            probe_count: 0,
            announce_count: 0,
            announce_interval: @initial_announce_interval,
            conflict_count: 0,
            hostname: "",
            original_hostname: "",
            records: []

  @doc """
  Start a new probe sequence for the given hostname and records.

  Returns `{probe_state, actions}`.
  """
  @spec new(String.t(), [DNS.dns_rr()]) :: {t(), [action()]}
  def new(hostname, records) do
    state = %__MODULE__{
      hostname: hostname,
      original_hostname: hostname,
      records: records
    }

    # RFC 6762 §8.1: First probe delay is random 0-250ms
    initial_delay = :rand.uniform(@probe_interval) - 1
    {state, [{:schedule_timer, initial_delay}]}
  end

  @doc """
  Handle a timer firing. Advances the state machine.

  Returns `{new_state, actions}`.
  """
  @spec timer_fired(t()) :: {t(), [action()]}
  def timer_fired(%{phase: :probing, probe_count: count} = state) when count < @probe_count do
    probe_packet = build_probe(state)
    new_state = %{state | probe_count: count + 1}
    {new_state, [{:send_probe, probe_packet}, {:schedule_timer, @probe_interval}]}
  end

  def timer_fired(%{phase: :probing, probe_count: @probe_count} = state) do
    # Probing complete, transition to announcing
    announcement = build_announcement(state)

    new_state = %{
      state
      | phase: :announcing,
        announce_count: 1,
        announce_interval: @initial_announce_interval
    }

    {new_state,
     [{:send_announcement, announcement}, {:schedule_timer, @initial_announce_interval}]}
  end

  def timer_fired(%{phase: :announcing, announce_count: count} = state)
      when count < @announce_count do
    announcement = build_announcement(state)
    next_interval = state.announce_interval * 2
    new_state = %{state | announce_count: count + 1, announce_interval: next_interval}
    {new_state, [{:send_announcement, announcement}, {:schedule_timer, next_interval}]}
  end

  def timer_fired(%{phase: :announcing} = state) do
    # Announcing complete
    new_state = %{state | phase: :running}
    {new_state, [:complete]}
  end

  def timer_fired(%{phase: :running} = state) do
    {state, []}
  end

  @doc """
  Handle a conflict detected on the network.

  A conflict means another host is using the same name. We must pick a new name
  and re-probe (RFC 6762 §8.1).

  Returns `{new_state, actions}`.
  """
  @spec conflict_detected(t()) :: {t(), [action()]}
  def conflict_detected(%{phase: phase} = state)
      when phase in [:probing, :announcing, :running] do
    new_conflict_count = state.conflict_count + 1
    new_hostname = conflict_rename(state.original_hostname, new_conflict_count)

    new_state = %{
      state
      | phase: :probing,
        probe_count: 0,
        announce_count: 0,
        announce_interval: @initial_announce_interval,
        conflict_count: new_conflict_count,
        hostname: new_hostname
    }

    # RFC 6762 §8.1: After 15 conflicts, rate limit to one probe per 5 seconds
    if new_conflict_count >= @max_conflicts_before_rate_limit do
      {new_state, [{:rename, new_hostname}, {:schedule_timer, @conflict_rate_limit_delay}]}
    else
      initial_delay = :rand.uniform(@probe_interval) - 1
      {new_state, [{:rename, new_hostname}, {:schedule_timer, initial_delay}]}
    end
  end

  @doc """
  Handle a simultaneous probe received from another host during our probing phase.

  RFC 6762 §8.2: Compare our proposed records with theirs lexicographically.
  If we lose, treat it as a conflict. If we win, ignore.

  Returns `{new_state, actions}`.
  """
  @spec simultaneous_probe_received(t(), [DNS.dns_rr()]) :: {t(), [action()]}
  def simultaneous_probe_received(%{phase: :probing} = state, their_records) do
    our_sorted = sort_for_tiebreak(state.records)
    their_sorted = sort_for_tiebreak(their_records)

    if we_lose_tiebreak?(our_sorted, their_sorted) do
      # We lose - wait 1 second then restart probing
      new_state = %{state | probe_count: 0}
      {new_state, [{:schedule_timer, 1000}]}
    else
      # We win - ignore
      {state, []}
    end
  end

  def simultaneous_probe_received(state, _their_records) do
    {state, []}
  end

  @doc """
  Check if a name matches what we're probing for.
  """
  @spec probing_name?(t(), charlist()) :: boolean()
  def probing_name?(%{phase: :probing, records: records}, domain) do
    lower_domain = :string.lowercase(domain)

    Enum.any?(records, fn dns_rr(domain: d) ->
      is_list(d) and :string.lowercase(d) == lower_domain
    end)
  end

  def probing_name?(_, _), do: false

  # Build a probe packet (RFC 6762 §8.1)
  # QR=0, AA=0; questions for our names; authority section has our proposed records
  @spec build_probe(t()) :: DNS.dns_rec()
  defp build_probe(state) do
    questions = probe_questions(state.records)

    # Authority records must NOT have cache-flush bit set during probing
    authority = Enum.map(state.records, &dns_rr(&1, func: false))

    dns_rec(
      header: dns_header(id: 0, qr: false, aa: false),
      qdlist: questions,
      nslist: authority
    )
  end

  # Build an announcement packet (RFC 6762 §8.3)
  # QR=1, AA=1; answers are our records with cache-flush bit set appropriately
  @spec build_announcement(t()) :: DNS.dns_rec()
  defp build_announcement(state) do
    dns_rec(
      header: dns_header(id: 0, qr: true, aa: true),
      anlist: state.records
    )
  end

  # Extract unique QM questions from our records
  defp probe_questions(records) do
    records
    |> Enum.map(fn dns_rr(domain: domain, type: type, class: class) ->
      dns_query(domain: domain, type: type, class: class, unicast_response: true)
    end)
    |> Enum.uniq_by(fn dns_query(domain: d, type: t, class: c) -> {d, t, c} end)
  end

  # Sort records for tiebreaking comparison (RFC 6762 §8.2)
  # Compare by {class, type, rdata} lexicographically
  defp sort_for_tiebreak(records) do
    records
    |> Enum.map(fn rr ->
      {dns_rr(rr, :class), dns_rr(rr, :type), encode_rdata(rr)}
    end)
    |> Enum.sort()
  end

  defp encode_rdata(rr) do
    # Encode just the rdata portion for comparison.
    # Use the raw data field value for comparison.
    dns_rr(rr, :data)
  end

  # RFC 6762 §8.2: We lose if their sorted records are lexicographically greater
  defp we_lose_tiebreak?(ours, theirs) do
    theirs > ours
  end

  # Generate a conflict-renamed hostname
  # "hostname" → "hostname-2" → "hostname-3" etc.
  defp conflict_rename(original_hostname, conflict_count) do
    "#{original_hostname}-#{conflict_count + 1}"
  end
end
