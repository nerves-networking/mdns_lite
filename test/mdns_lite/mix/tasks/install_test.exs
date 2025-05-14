defmodule MdnsLite.Mix.Tasks.InstallTest do
  use ExUnit.Case, async: true
  import Igniter.Test

  test "installer warns if no target.exs is present" do
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
    |> assert_has_warning(fn w ->
      "mix mdns_lite.install is not yet implemented for non-Nerves projects" == w
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
    |> assert_has_patch("config/target.exs", ~S"""
      3 + |config :mdns_lite,
      4 + |  host: [hostname: "nerves"],
      5 + |  ttl: 120,
      6 + |  services: [
      7 + |    %{port: 22, protocol: "ssh", transport: "tcp"},
      8 + |    %{port: 22, protocol: "sftp-ssh", transport: "tcp"},
      9 + |    %{port: 4369, protocol: "epmd", transport: "tcp"}
     10 + |  ]
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
    9    - |  ]
       9 + |  ],
      10 + |  ttl: 120
    """)
  end
end
