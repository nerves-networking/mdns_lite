defmodule MdnsLite.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    config = MdnsLite.Options.from_application_env()

    children = [
      {MdnsLite.TableServer, config},
      {Registry, keys: :unique, name: MdnsLite.ResponderRegistry},
      {Registry, keys: :duplicate, name: MdnsLite.Responders},
      {MdnsLite.ResponderSupervisor, []},
      {MdnsLite.DNSBridge, config},
      {config.if_monitor, excluded_ifnames: config.excluded_ifnames, ipv4_only: config.ipv4_only}
    ]

    opts = [strategy: :rest_for_one, name: MdnsLite.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
