# SPDX-FileCopyrightText: 2019 Frank Hunleth
# SPDX-FileCopyrightText: 2019 Jon Carstens
# SPDX-FileCopyrightText: 2019 Peter C. Marks
# SPDX-FileCopyrightText: 2020 Eduardo Cunha
# SPDX-FileCopyrightText: 2021 Mat Trudel
#
# SPDX-License-Identifier: Apache-2.0
#
import Config

config :mdns_lite,
  # Use these values to construct the DNS resource record responses
  # to a DNS query.
  # host can be one of the values: hostname1, [hostname1], or [hostname1, hostname2]
  # where hostname1 is the atom :hostname in which case it is replaced with the
  # value of :inet.gethostname() or a string and hostname2 is a string value.
  # Example: [:hostname, "nerves"]

  hosts: [:hostname, "nerves"],
  ttl: 120,

  # instance_name is a user friendly name that will be used as the name for this
  # device's advertised service(s). Per RFC6763 Appendix C, this should describe
  # the user-facing purpose or description of the device, and should not be
  # considered a unique identifier. For example, 'Nerves Device' and 'MatCo
  # Laser Printer Model CRM-114' are good choices here.  If instance_name is not
  # defined it defaults to the first entry in the `hosts` list above
  #
  # instance_name: "mDNS Lite Device",

  # A list of this host's services. NB: There are two other mDNS values: weight
  # and priority that both default to zero unless included in the service below.
  # The txt_payload value is optional and can be used to define the data in TXT
  # DNS resource records, it should be a list of strings containing a key and
  # value separated by a '='.
  services: [
    %{
      id: :web_server,
      protocol: "http",
      transport: "tcp",
      port: 80,
      txt_payload: ["key=value"]
    },
    %{
      id: :ssh_daemon,
      protocol: "ssh",
      transport: "tcp",
      port: 22
    }
  ],
  if_monitor: MdnsLite.InetMonitor

# Overrides for debugging and testing
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

if Mix.env() == :test do
  # Allow Responders to still be created, but skip starting gen_udp
  # so tests can pass
  config :mdns_lite,
    skip_udp: true
end
