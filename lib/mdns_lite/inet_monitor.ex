defmodule MdnsLite.InetMonitor do
  use GenServer

  require Logger

  alias MdnsLite.CoreMonitor

  @scan_interval 10000

  @moduledoc false

  # Watch :inet.getifaddrs/0 for IP address changes and update the active responders.

  @doc """
  Start watching for changes on the specified network interfaces.

  Parameters

    * `:excluded_ifnames` - the list of interface names not to watch
    * `:ipv4_only` - limit notifications to IPv4 addresses
  """
  @spec start_link([CoreMonitor.option()]) :: GenServer.on_start()
  def start_link(init_args) do
    GenServer.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  @impl GenServer
  def init(args) do
    {:ok, CoreMonitor.init(args), 1}
  end

  @impl GenServer
  def handle_info(:timeout, state) do
    {:noreply, update(state), @scan_interval}
  end

  defp update(state) do
    get_all_ip_addrs()
    |> Enum.reduce(state, fn {ifname, ip_list}, state ->
      CoreMonitor.set_ip_list(state, ifname, ip_list)
    end)
    |> CoreMonitor.flush_todo_list()
  end

  defp get_all_ip_addrs() do
    case :inet.getifaddrs() do
      {:ok, ifaddrs} ->
        Enum.map(ifaddrs, &ifaddr_to_ip_list/1)

      _error ->
        []
    end
  end

  defp ifaddr_to_ip_list({ifname, info}) do
    addrs = for addr <- Keyword.get_values(info, :addr), do: addr
    {to_string(ifname), addrs}
  end
end
