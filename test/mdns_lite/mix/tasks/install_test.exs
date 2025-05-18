defmodule MdnsLite.Mix.Tasks.InstallTest do
  use ExUnit.Case, async: true
  import Igniter.Test

  test "installer modifies config.exs but warns if no target.exs is present" do
    test_project(
      files: %{
        "config/config.exs" => """
        import Config
        config :logger, level: :info
        config :other_thing, foo: :bar
        """
      }
    )
    |> Igniter.compose_task("mdns_lite.install", [])
    |> assert_has_patch("config/config.exs", """
      + |config :mdns_lite,
      + |  host: [hostname: "nerves"],
      + |  ttl: 120,
      + |  services: [
      + |    %{port: 22, protocol: "ssh", transport: "tcp"},
      + |    %{port: 22, protocol: "sftp-ssh", transport: "tcp"},
      + |    %{port: 4369, protocol: "epmd", transport: "tcp"}
      + |  ]
      + |
    """)
    |> assert_has_notice(fn notice ->
      """
      The defaults for `mix mdns_lite.install` are intended for Nerves projects.  Please visit
      its README at https://hexdocs.pm/mdns_lite/readme.html for an overview of usage.
      """ == notice
    end)
  end

  test "installer adds default mdns_lite values for target.exs" do
    test_project(
      files: %{
        "config/target.exs" => """
        import Config

        config :other_thing, foo: :bar
        """
      }
    )
    |> Igniter.compose_task("mdns_lite.install", [])
    |> assert_has_patch("config/target.exs", """
      + |config :mdns_lite,
      + |  host: [hostname: "nerves"],
      + |  ttl: 120,
      + |  services: [
      + |    %{port: 22, protocol: "ssh", transport: "tcp"},
      + |    %{port: 22, protocol: "sftp-ssh", transport: "tcp"},
      + |    %{port: 4369, protocol: "epmd", transport: "tcp"}
      + |  ]
    """)
  end

  test "installer leaves mdns values in place if already present" do
    test_project(
      files: %{
        "config/target.exs" => """
        import Config

        config :mdns_lite,
          host: [hostname: "my-nerves-device"],
          services: [
            %{port: 2222, protocol: "ssh", transport: "tcp"},
            %{port: 2222, protocol: "sftp-ssh", transport: "tcp"},
            %{port: 4369, protocol: "epmd", transport: "tcp"}
          ]
        """
      }
    )
    |> Igniter.compose_task("mdns_lite.install", [])
    |> assert_has_patch("config/target.exs", ~S"""
      - |  ]
      + |  ],
      + |  ttl: 120
    """)
  end
end
