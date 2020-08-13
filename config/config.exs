# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :mdns_lite,
  # Use these values to construct the DNS resource record responses
  # to a DNS query.
  # host can be one of the values: hostname1, [hostname1], or [hostname1, hostname2]
  # where hostname1 is the atom :hostname in which case it is replaced with the
  # value of :int.gethostname() or a string and hostname2 is a string value.
  # Exmple: [:hostname, "nerves"]

  host: [:hostname, "nerves"],
  ttl: 120,

  # A list of this host's services. NB: There are two other mDNS values: weight
  # and priority that both default to zero unless included in the service below.
  # The txt_payload value is optional and can be used to define the data in TXT
  # DNS resource records, it should be a list of strings containing a key and
  # value separated by a '='.
  services: [
    %{
      name: "Web Server",
      protocol: "http",
      transport: "tcp",
      port: 80,
      txt_payload: ["key=value"]
    },
    %{
      name: "Secure Socket",
      protocol: "ssh",
      transport: "tcp",
      port: 22
    }
  ]

if Mix.env() == :test do
  # Allow Responders to still be created, but skip starting gen_udp
  # so tests can pass
  config :mdns_lite,
    skip_udp: true

  # Overrides for unit tests:
  #
  # * udhcpc_handler: capture whatever happens with udhcpc
  # * resolvconf: don't update the real resolv.conf
  # * persistence_dir: use the current directory
  # * bin_ip: just fail if anything calls ip rather that run it
  config :vintage_net,
    udhcpc_handler: VintageNetTest.CapturingUdhcpcHandler,
    resolvconf: "/dev/null",
    persistence_dir: "./test_tmp/persistence",
    bin_ip: "false"
end

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
