defmodule MdnsLite.Application do
  @moduledoc false

  use Application

  defmodule RuntimeSupervisor do
    use Supervisor

    @moduledoc false

    def start_link(init_arg) do
      Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
    end

    @impl Supervisor
    def init(_init_arg) do
      ip_address_monitor =
        Application.get_env(
          :mdns_lite,
          :ip_address_monitor,
          default_monitor()
        )

      children = [
        {Registry, keys: :unique, name: MdnsLite.ResponderRegistry},
        {MdnsLite.ResponderSupervisor, []},
        ip_address_monitor
      ]

      Supervisor.init(children, strategy: :one_for_all)
    end

    defp default_monitor() do
      excluded_ifnames =
        Application.get_env(:mdns_lite, :excluded_ifnames, ["lo0", "lo", "ppp0", "wwan0"])

      if Code.ensure_loaded?(VintageNet) do
        {MdnsLite.VintageNetMonitor, excluded_ifnames: excluded_ifnames}
      else
        {MdnsLite.InetMonitor, excluded_ifnames: excluded_ifnames}
      end
    end
  end

  @impl Application
  def start(_type, _args) do
    children = [
      {MdnsLite.Configuration, []},
      RuntimeSupervisor
    ]

    opts = [strategy: :rest_for_one, name: MdnsLite.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
