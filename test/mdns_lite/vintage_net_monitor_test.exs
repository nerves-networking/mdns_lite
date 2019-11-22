defmodule MdnsLite.VintageNetMonitorTest do
  use ExUnit.Case, async: true

  alias MdnsLite.{VintageNetMonitor, ResponderSupervisor}

  setup do
    %{
      ipv4: %{
        address: {10, 0, 1, Enum.random(0..255)},
        family: :inet,
        netmask: {255, 255, 255, 0},
        prefix_length: 24,
        scope: :universe
      },
      ipv6: %{
        address: {10, 0, 1, 23, 0, 0, 0, 1},
        family: :inet6
      }
    }
  end

  test "can add ips from event", %{ipv4: ipv4} do
    event = {VintageNet, ["interface", "wlan0", "addresses"], [], [ipv4], %{}}

    responders = Supervisor.count_children(ResponderSupervisor).specs

    send(VintageNetMonitor, event)

    assert ipv4.address in :sys.get_state(VintageNetMonitor).ip_list
    assert Supervisor.count_children(ResponderSupervisor).active == responders + 1
  end

  test "can remove ips from event", %{ipv4: ipv4} do
    event = {VintageNet, ["interface", "wlan0", "addresses"], [ipv4], [], %{}}

    :sys.replace_state(VintageNetMonitor, fn state ->
      %{state | ip_list: MapSet.new([ipv4.address])}
    end)

    responders = Supervisor.count_children(ResponderSupervisor).specs

    assert ipv4.address in :sys.get_state(VintageNetMonitor).ip_list

    send(VintageNetMonitor, event)

    assert ipv4.address not in :sys.get_state(VintageNetMonitor).ip_list
    assert Supervisor.count_children(ResponderSupervisor).active == responders
  end

  test "can ignore ipv6", %{ipv6: ipv6} do
    event = {VintageNet, ["interface", "wlan0", "addresses"], [], [ipv6], %{}}

    send(VintageNetMonitor, event)

    assert ipv6.address not in :sys.get_state(VintageNetMonitor).ip_list
  end

  test "can exclude ifnames", %{ipv4: ipv4} do
    :sys.replace_state(VintageNetMonitor, fn state -> %{state | excluded_ifnames: ["wat"]} end)
    event = {VintageNet, ["interface", "wat", "addresses"], [], [ipv4], %{}}

    send(VintageNetMonitor, event)

    assert ipv4.address not in :sys.get_state(VintageNetMonitor).ip_list
  end
end
