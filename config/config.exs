# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :mdns_lite,
  # Use these values to construct the DNS resource record responses
  # to a DNS query.
  mdns_config: %{
    host: :hostname,
    ttl: 3600,
    query_types: [
      # IP address lookup,
      :a,
      # Reverse IP lookup
      :ptr,
      # Services - see below
      :srv
    ]
  },
  services: [
    # service type: _http._tcp - used in match
    %{
      type: "_http._tcp",
      name: "Web Server",
      protocol: "http",
      transport: "tcp",
      port: 80,
      weight: 0,
      priority: 0
    },
    # TODO: service_type: _ssh._tcp
    %{
      type: "_ssh._tcp",
      name: "Secure Socket",
      protocol: "ssh",
      transport: "tcp",
      port: 22,
      weight: 0,
      priority: 0
    }
  ]

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# third-party users, it should be done in your "mix.exs" file.

# You can configure your application as:
#
#     config :mdns_lite, key: :value
#
# and access this configuration in your application as:
#
#     Application.get_env(:mdns_lite, :key)
#
# You can also configure a third-party app:
#
#     config :logger, level: :info
#

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
#     import_config "#{Mix.env()}.exs"
