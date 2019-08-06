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
      children = [
        {Registry, keys: :unique, name: MdnsLite.ResponderRegistry},
        {MdnsLite.ResponderSupervisor, []}
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
