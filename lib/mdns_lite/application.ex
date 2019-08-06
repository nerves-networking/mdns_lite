defmodule MdnsLite.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {MdnsLite.Configuration, []}
    ]

    opts = [strategy: :one_for_one, name: MdnsLite.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
