defmodule MdnsLite.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    excluded_ifnames =
      Application.get_env(:mdns_lite, :excluded_ifnames, ["lo0", "lo", "ppp0", "wwan0"])

    config = MdnsLite.Options.from_application_env()

    children = [
      {MdnsLite.TableServer, config},
      {Registry, keys: :unique, name: MdnsLite.ResponderRegistry},
      {MdnsLite.ResponderSupervisor, []},
      {MdnsLite.VintageNetMonitor, excluded_ifnames: excluded_ifnames}
    ]

    opts = [strategy: :rest_for_one, name: MdnsLite.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
