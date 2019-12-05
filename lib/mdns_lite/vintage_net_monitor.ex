defmodule MdnsLite.VintageNetMonitor do
  use GenServer

  alias MdnsLite.{Responder, ResponderSupervisor}

  @addresses_topic ["interface", :_, "addresses"]

  defmodule State do
    @moduledoc false

    defstruct [:excluded_ifnames, :ipv4_only, :ip_list]
  end

  @spec start_link(excluded_ifnames: [String.t()], ipv4_only: boolean()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    excluded_ifnames =
      Keyword.get(opts, :excluded_ifnames, [])
      |> Enum.map(&to_string/1)

    ipv4_only = Keyword.get(opts, :ipv4_only, true)

    state = %State{
      excluded_ifnames: excluded_ifnames,
      ip_list: MapSet.new(),
      ipv4_only: ipv4_only
    }

    _ = VintageNet.subscribe(@addresses_topic)

    {:ok, state, {:continue, :initialization}}
  end

  @impl true
  def handle_continue(:initialization, state) do
    address_data =
      VintageNet.match(@addresses_topic)
      |> Stream.filter(&allowed_interface?(&1, state))
      |> Enum.map(&elem(&1, 1))
      |> List.flatten()

    {:noreply, add_ips(state, address_data)}
  end

  @impl true
  def handle_info({VintageNet, ["interface", ifname, "addresses"], old, new, _}, state) do
    new_state =
      if allowed_interface?(ifname, state) do
        state
        |> remove_ips(old)
        |> add_ips(new)
      else
        state
      end

    {:noreply, new_state}
  end

  defp add_ips(state, nil), do: state

  defp add_ips(%{ip_list: ip_list} = state, address_data) do
    ip_list =
      fetch_ips(address_data)
      |> filter_by_ipv4(state.ipv4_only)
      |> Enum.reduce(ip_list, fn ip, acc ->
        _ = ResponderSupervisor.start_child(ip)
        MapSet.put(acc, ip)
      end)

    %{state | ip_list: ip_list}
  end

  defp allowed_interface?({["interface", ifname, _], _}, state) do
    allowed_interface?(ifname, state)
  end

  defp allowed_interface?(ifname, %{excluded_ifnames: excluded_ifnames}) do
    ifname not in excluded_ifnames
  end

  defp fetch_ips(ip_list), do: Enum.map(ip_list, & &1.address)

  defp filter_by_ipv4(ip_list, false) do
    ip_list
  end

  defp filter_by_ipv4(ip_list, true) do
    Enum.filter(ip_list, &(MdnsLite.Utilities.ip_family(&1) == :inet))
  end

  defp remove_ips(state, nil), do: state

  defp remove_ips(%{ip_list: ip_list} = state, address_data) do
    ip_list =
      fetch_ips(address_data)
      |> Enum.reduce(ip_list, fn ip, acc ->
        _ = Responder.stop_server(ip)
        MapSet.delete(acc, ip)
      end)

    %{state | ip_list: ip_list}
  end
end
