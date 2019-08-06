defmodule MdnsLite.Application do
  @moduledoc false

  use Application

  defmodule RuntimeSupervisor do
    use Supervisor

    @moduledoc false

    def start_link(init_arg) do
      Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
    end

    @impl true
    def init(_init_arg) do
      excluded_ifnames = Application.get_env(:mdns_lite, :excluded_ifnames, ["lo0", "lo"])

      children = [
        {Registry, keys: :unique, name: MdnsLite.ResponderRegistry},
        {MdnsLite.ResponderSupervisor, []},
        {MdnsLite.InetMonitor, excluded_ifnames: excluded_ifnames}
      ]

      Supervisor.init(children, strategy: :one_for_all)
    end
  end

  @impl true
  def start(_type, _args) do
    children = [
      {MdnsLite.Configuration, []},
      RuntimeSupervisor
    ]

    opts = [strategy: :rest_for_one, name: MdnsLite.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
