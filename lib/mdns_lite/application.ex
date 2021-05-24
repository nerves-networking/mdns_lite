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
      excluded_ifnames =
        Application.get_env(:mdns_lite, :excluded_ifnames, ["lo0", "lo", "ppp0", "wwan0"])

      children = [
        {Registry, keys: :unique, name: MdnsLite.ResponderRegistry},
        {MdnsLite.ResponderSupervisor, []},
        {MdnsLite.VintageNetMonitor, excluded_ifnames: excluded_ifnames}
      ]

      Supervisor.init(children, strategy: :one_for_all)
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
