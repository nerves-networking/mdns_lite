# SPDX-FileCopyrightText: 2026 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule MdnsLite.ProbeTest do
  use ExUnit.Case, async: true

  import MdnsLite.DNS

  alias MdnsLite.Probe

  defp test_records() do
    [
      dns_rr(
        domain: ~c"nerves-21a5.local",
        type: :a,
        class: :in,
        ttl: 120,
        data: :ipv4_address,
        func: true
      ),
      dns_rr(
        domain: ~c"nerves-21a5.local",
        type: :aaaa,
        class: :in,
        ttl: 120,
        data: :ipv6_address,
        func: true
      )
    ]
  end

  describe "new/2" do
    test "starts in probing phase with an initial timer" do
      {state, actions} = Probe.new("nerves-21a5", test_records())

      assert state.phase == :probing
      assert state.probe_count == 0
      assert state.hostname == "nerves-21a5"
      assert state.original_hostname == "nerves-21a5"

      assert [{:schedule_timer, delay}] = actions
      assert delay >= 0 and delay < 250
    end
  end

  describe "probing phase" do
    test "sends 3 probes spaced 250ms apart" do
      {state, _} = Probe.new("nerves-21a5", test_records())

      # First timer fires -> send probe 1
      {state, actions1} = Probe.timer_fired(state)
      assert state.probe_count == 1
      assert [{:send_probe, probe1}, {:schedule_timer, 250}] = actions1
      assert dns_rec(probe1, :header) |> dns_header(:qr) == false
      assert dns_rec(probe1, :header) |> dns_header(:aa) == false
      assert dns_rec(probe1, :qdlist) != []
      assert dns_rec(probe1, :nslist) != []

      # Second timer fires -> send probe 2
      {state, actions2} = Probe.timer_fired(state)
      assert state.probe_count == 2
      assert [{:send_probe, _}, {:schedule_timer, 250}] = actions2

      # Third timer fires -> send probe 3
      {state, actions3} = Probe.timer_fired(state)
      assert state.probe_count == 3
      assert [{:send_probe, _}, {:schedule_timer, 250}] = actions3

      # Fourth timer fires -> transition to announcing
      {state, actions4} = Probe.timer_fired(state)
      assert state.phase == :announcing
      assert [{:send_announcement, _}, {:schedule_timer, 1000}] = actions4
    end

    test "probe packet has no cache-flush bit in authority records" do
      {state, _} = Probe.new("nerves-21a5", test_records())
      {_state, [{:send_probe, probe}, _]} = Probe.timer_fired(state)

      for rr <- dns_rec(probe, :nslist) do
        assert dns_rr(rr, :func) == false
      end
    end

    test "probe questions have unicast_response set" do
      {state, _} = Probe.new("nerves-21a5", test_records())
      {_state, [{:send_probe, probe}, _]} = Probe.timer_fired(state)

      for q <- dns_rec(probe, :qdlist) do
        assert dns_query(q, :unicast_response) == true
      end
    end
  end

  describe "announcing phase" do
    setup do
      {state, _} = Probe.new("nerves-21a5", test_records())

      # Run through all 3 probes
      {state, _} = Probe.timer_fired(state)
      {state, _} = Probe.timer_fired(state)
      {state, _} = Probe.timer_fired(state)

      # Transition to announcing
      {state, _} = Probe.timer_fired(state)
      assert state.phase == :announcing

      {:ok, state: state}
    end

    test "sends announcements with interval doubling", %{state: state} do
      # announce_count starts at 1, interval at 1000
      assert state.announce_count == 1

      {state, actions} = Probe.timer_fired(state)
      assert state.announce_count == 2
      assert [{:send_announcement, _}, {:schedule_timer, 2000}] = actions

      {state, actions} = Probe.timer_fired(state)
      assert state.announce_count == 3
      assert [{:send_announcement, _}, {:schedule_timer, 4000}] = actions

      {state, actions} = Probe.timer_fired(state)
      assert state.announce_count == 4
      assert [{:send_announcement, _}, {:schedule_timer, 8000}] = actions
    end

    test "transitions to running after 8 announcements", %{state: state} do
      # We already sent 1 announcement. Send 7 more.
      state =
        Enum.reduce(1..7, state, fn _, s ->
          {s, _} = Probe.timer_fired(s)
          s
        end)

      assert state.announce_count == 8

      # Next timer -> complete
      {state, actions} = Probe.timer_fired(state)
      assert state.phase == :running
      assert actions == [:complete]
    end

    test "announcement packet has QR=true and AA=true", %{state: state} do
      {_state, [{:send_announcement, announcement}, _]} = Probe.timer_fired(state)

      header = dns_rec(announcement, :header)
      assert dns_header(header, :qr) == true
      assert dns_header(header, :aa) == true
    end
  end

  describe "conflict_detected/1" do
    test "during probing, renames and restarts probing" do
      {state, _} = Probe.new("nerves-21a5", test_records())
      {state, _} = Probe.timer_fired(state)

      {state, actions} = Probe.conflict_detected(state)
      assert state.phase == :probing
      assert state.probe_count == 0
      assert state.hostname == "nerves-21a5-2"
      assert state.conflict_count == 1

      assert [{:rename, "nerves-21a5-2"}, {:schedule_timer, _delay}] = actions
    end

    test "multiple conflicts increment suffix" do
      {state, _} = Probe.new("nerves-21a5", test_records())

      {state, _} = Probe.conflict_detected(state)
      assert state.hostname == "nerves-21a5-2"

      {state, _} = Probe.conflict_detected(state)
      assert state.hostname == "nerves-21a5-3"

      {state, _} = Probe.conflict_detected(state)
      assert state.hostname == "nerves-21a5-4"
    end

    test "rate limits after 15 conflicts" do
      {state, _} = Probe.new("nerves-21a5", test_records())

      # Generate 15 conflicts
      state =
        Enum.reduce(1..15, state, fn _, s ->
          {s, _} = Probe.conflict_detected(s)
          s
        end)

      assert state.conflict_count == 15

      # 16th conflict should be rate-limited
      {_state, actions} = Probe.conflict_detected(state)
      assert [{:rename, _}, {:schedule_timer, 5000}] = actions
    end

    test "conflicts before rate limit have normal delay" do
      {state, _} = Probe.new("nerves-21a5", test_records())

      {_state, actions} = Probe.conflict_detected(state)
      [{:rename, _}, {:schedule_timer, delay}] = actions
      assert delay >= 0 and delay < 250
    end

    test "during running phase, renames and re-probes" do
      {state, _} = Probe.new("nerves-21a5", test_records())

      # Fast-forward to running
      state = %{state | phase: :running, probe_count: 3, announce_count: 8}

      {state, actions} = Probe.conflict_detected(state)
      assert state.phase == :probing
      assert state.probe_count == 0
      assert [{:rename, "nerves-21a5-2"}, {:schedule_timer, _}] = actions
    end
  end

  describe "simultaneous_probe_received/2" do
    test "ignores when not probing" do
      {state, _} = Probe.new("nerves-21a5", test_records())
      state = %{state | phase: :running}

      their_records = [
        dns_rr(domain: ~c"nerves-21a5.local", type: :a, class: :in, data: {10, 0, 0, 1})
      ]

      {new_state, actions} = Probe.simultaneous_probe_received(state, their_records)
      assert new_state == state
      assert actions == []
    end

    test "we win tiebreak when our data is greater, ignores probe" do
      records = [
        dns_rr(domain: ~c"nerves-21a5.local", type: :a, class: :in, data: {192, 168, 9, 57})
      ]

      {state, _} = Probe.new("nerves-21a5", records)

      # Their IP is lower, so we win
      their_records = [
        dns_rr(domain: ~c"nerves-21a5.local", type: :a, class: :in, data: {10, 0, 0, 1})
      ]

      {new_state, actions} = Probe.simultaneous_probe_received(state, their_records)
      assert new_state.probe_count == state.probe_count
      assert actions == []
    end

    test "we lose tiebreak when their data is greater, restarts probing" do
      records = [
        dns_rr(domain: ~c"nerves-21a5.local", type: :a, class: :in, data: {10, 0, 0, 1})
      ]

      {state, _} = Probe.new("nerves-21a5", records)

      # Their IP is higher, so we lose
      their_records = [
        dns_rr(domain: ~c"nerves-21a5.local", type: :a, class: :in, data: {192, 168, 9, 57})
      ]

      {new_state, actions} = Probe.simultaneous_probe_received(state, their_records)
      assert new_state.probe_count == 0
      assert [{:schedule_timer, 1000}] = actions
    end
  end

  describe "probing_name?/2" do
    test "returns true during probing for matching domain" do
      {state, _} = Probe.new("nerves-21a5", test_records())
      assert Probe.probing_name?(state, ~c"nerves-21a5.local")
    end

    test "case-insensitive match" do
      {state, _} = Probe.new("nerves-21a5", test_records())
      assert Probe.probing_name?(state, ~c"NERVES-21A5.LOCAL")
    end

    test "returns false for non-matching domain" do
      {state, _} = Probe.new("nerves-21a5", test_records())
      refute Probe.probing_name?(state, ~c"other-host.local")
    end

    test "returns false when not probing" do
      {state, _} = Probe.new("nerves-21a5", test_records())
      state = %{state | phase: :running}
      refute Probe.probing_name?(state, ~c"nerves-21a5.local")
    end
  end
end
