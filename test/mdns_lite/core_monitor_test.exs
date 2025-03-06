# SPDX-FileCopyrightText: 2021 Frank Hunleth
# SPDX-FileCopyrightText: 2024 Kevin Schweikert
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule MdnsLite.CoreMonitorTest do
  use ExUnit.Case, async: true

  alias MdnsLite.CoreMonitor

  test "adding IPs" do
    state =
      CoreMonitor.init([])
      |> CoreMonitor.set_ip_list("eth0", [{1, 2, 3, 4}, {1, 2, 3, 4, 5, 6, 7, 8}])
      |> CoreMonitor.set_ip_list("wlan0", [{10, 11, 12, 13}, {14, 15, 16, 17}])

    # IPv4 filtering is on by default
    assert state.todo == [
             {MdnsLite.ResponderSupervisor, :start_child, ["eth0", {1, 2, 3, 4}]},
             {MdnsLite.ResponderSupervisor, :start_child, ["wlan0", {10, 11, 12, 13}]},
             {MdnsLite.ResponderSupervisor, :start_child, ["wlan0", {14, 15, 16, 17}]}
           ]
  end

  test "removing IPs" do
    state =
      CoreMonitor.init([])
      |> CoreMonitor.set_ip_list("eth0", [{1, 2, 3, 4}, {5, 6, 7, 8}])
      |> CoreMonitor.set_ip_list("eth0", [{5, 6, 7, 8}])

    assert state.todo == [
             {MdnsLite.ResponderSupervisor, :start_child, ["eth0", {1, 2, 3, 4}]},
             {MdnsLite.ResponderSupervisor, :start_child, ["eth0", {5, 6, 7, 8}]},
             {MdnsLite.ResponderSupervisor, :stop_child, ["eth0", {1, 2, 3, 4}]}
           ]
  end

  test "applying the todo list works" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    state =
      CoreMonitor.init([])
      |> Map.put(:todo, [
        {Agent, :update, [agent, fn x -> x + 1 end]},
        {Agent, :update, [agent, fn x -> x + 1 end]}
      ])
      |> CoreMonitor.flush_todo_list()

    assert state.todo == []
    assert Agent.get(agent, fn x -> x end) == 2
  end

  test "filtering interfaces" do
    state =
      CoreMonitor.init(excluded_ifnames: ["wlan0"])
      |> CoreMonitor.set_ip_list("eth0", [{1, 2, 3, 4}, {1, 2, 3, 4, 5, 6, 7, 8}])
      |> CoreMonitor.set_ip_list("wlan0", [{10, 11, 12, 13}, {14, 15, 16, 17}])

    # IPv4 filtering is on by default
    assert state.todo == [
             {MdnsLite.ResponderSupervisor, :start_child, ["eth0", {1, 2, 3, 4}]}
           ]
  end

  test "allowing IPv6" do
    state =
      CoreMonitor.init(ipv4_only: false)
      |> CoreMonitor.set_ip_list("eth0", [{1, 2, 3, 4}, {1, 2, 3, 4, 5, 6, 7, 8}])

    # IPv4 filtering is on by default
    assert state.todo == [
             {MdnsLite.ResponderSupervisor, :start_child, ["eth0", {1, 2, 3, 4}]},
             {MdnsLite.ResponderSupervisor, :start_child, ["eth0", {1, 2, 3, 4, 5, 6, 7, 8}]}
           ]
  end

  test "remove unset ifnames" do
    state =
      CoreMonitor.init([])
      |> CoreMonitor.set_ip_list("eth0", [{1, 2, 3, 4}, {1, 2, 3, 4, 5, 6, 7, 8}])
      |> CoreMonitor.set_ip_list("wlan0", [{10, 11, 12, 13}, {14, 15, 16, 17}])
      |> CoreMonitor.flush_todo_list()

    state =
      state
      |> CoreMonitor.set_ip_list("wlan0", [{10, 11, 12, 13}])
      |> CoreMonitor.unset_remaining_ifnames(["wlan0"])

    # IPv4 filtering is on by default
    assert state.todo == [
             {MdnsLite.ResponderSupervisor, :stop_child, ["wlan0", {14, 15, 16, 17}]},
             {MdnsLite.ResponderSupervisor, :stop_child, ["eth0", {1, 2, 3, 4}]}
           ]
  end
end
