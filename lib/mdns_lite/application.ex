defmodule MdnsLite.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @mdns_config Application.get_env(:mdns_lite, :mdns_config)
  @mdns_services Application.get_env(:mdns_lite, :services)
  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      # Start the GenServer that is responsible for maintaining a set of
      # mDNS service responders - one per network interface. Initialize
      # it with some values that are used to construct DNS responses
      # and some optional services
      {MdnsLite, [@mdns_config, @mdns_services]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MdnsLite.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
