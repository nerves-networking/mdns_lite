# SPDX-FileCopyrightText: 2025 Lee Nussbaum
# SPDX-FileCopyrightText: 2026 Frank Hunleth
# SPDX-FileCopyrightText: 2026 Lars Wikman
#
# SPDX-License-Identifier: Apache-2.0
#

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
      + |  hosts: [:hostname, "nerves"],
      + |  ttl: 120,
      + |  services: [
      + |    %{protocol: "ssh", port: 22, transport: "tcp"},
      + |    %{protocol: "sftp-ssh", port: 22, transport: "tcp"},
      + |    %{protocol: "epmd", port: 4369, transport: "tcp"}
      + |  ]
      + |
    """)
    |> assert_has_notice("""
    The defaults for `mix mdns_lite.install` are intended for Nerves projects.  Please visit
    its README at https://mdns-lite.hexdocs.pm/readme.html for an overview of usage.
    """)
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
      + |  hosts: [:hostname, "nerves"],
      + |  ttl: 120,
      + |  services: [
      + |    %{protocol: "ssh", port: 22, transport: "tcp"},
      + |    %{protocol: "sftp-ssh", port: 22, transport: "tcp"},
      + |    %{protocol: "epmd", port: 4369, transport: "tcp"}
      + |  ]
    """)
  end

  test "installer leaves mdns values in place if already present" do
    test_project(
      files: %{
        "config/target.exs" => """
        import Config

        config :mdns_lite,
          hosts: ["my-nerves-device"],
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

  @nerves_new_target_exs """
  import Config

  config :mdns_lite,
    hosts: [:hostname, "nerves"],
    ttl: 120,
    services: [
      %{
        protocol: "ssh",
        transport: "tcp",
        port: 22
      }
    ]
  """

  test "installer changes nothing when the mix nerves.new config is present" do
    test_project(files: %{"config/target.exs" => @nerves_new_target_exs})
    |> Igniter.compose_task("mdns_lite.install", ["--hostname", "other"])
    |> assert_unchanged()
  end

  test "installer is idempotent" do
    test_project(files: %{"config/target.exs" => "import Config\n"})
    |> Igniter.compose_task("mdns_lite.install", [])
    |> apply_igniter!()
    |> Igniter.compose_task("mdns_lite.install", [])
    |> assert_unchanged()
  end

  test "--hostname sets the advertised alias" do
    test_project(files: %{"config/target.exs" => "import Config\n"})
    |> Igniter.compose_task("mdns_lite.install", ["--hostname", "my-hostname"])
    |> assert_has_patch("config/target.exs", """
      + |config :mdns_lite,
      + |  hosts: [:hostname, "my-hostname"],
    """)
  end

  test "generated config is accepted by MdnsLite.Options" do
    igniter =
      test_project(files: %{"config/target.exs" => "import Config\n"})
      |> Igniter.compose_task("mdns_lite.install", ["--hostname", "my-hostname"])
      |> apply_igniter!()

    content =
      igniter.rewrite |> Rewrite.source!("config/target.exs") |> Rewrite.Source.get(:content)

    config = Config.Reader.eval!("config/target.exs", content)
    options = MdnsLite.Options.new(config[:mdns_lite])

    {:ok, hostname} = :inet.gethostname()
    assert options.hosts == [to_string(hostname), "my-hostname"]
    assert options.ttl == 120
    assert MapSet.size(options.services) == 3
  end

  test "installer does not add hosts when the deprecated host option is set" do
    test_project(
      files: %{
        "config/target.exs" => """
        import Config

        config :mdns_lite, host: [:hostname, "nerves"], ttl: 60
        """
      }
    )
    |> Igniter.compose_task("mdns_lite.install", [])
    |> assert_has_patch("config/target.exs", """
      - |config :mdns_lite, host: [:hostname, "nerves"], ttl: 60
      + |config :mdns_lite,
      + |  host: [:hostname, "nerves"],
      + |  ttl: 60,
      + |  services: [
    """)
    |> assert_has_notice("""
    mdns_lite: your config sets the deprecated `:host` option, so `:hosts` was not added.
    Rename `host:` to `hosts:` in your `config :mdns_lite` to remove the deprecation warning.
    """)
  end

  test "installer leaves target.exs alone when config.exs already configures mdns_lite" do
    test_project(
      files: %{
        "config/config.exs" => """
        import Config

        config :mdns_lite,
          hosts: ["my-nerves-device"],
          ttl: 60,
          services: []

        import_config "target.exs"
        """,
        "config/target.exs" => "import Config\n"
      }
    )
    |> Igniter.compose_task("mdns_lite.install", [])
    |> assert_unchanged()
  end

  describe "restricting the dependency to the project's targets" do
    defp targets_mix_exs(deps) do
      """
      defmodule Test.MixProject do
        use Mix.Project

        @app :test
        @device_targets [:rpi4, :rpi5]
        @other_targets [:bbb]

        def project do
          [app: @app, version: "0.1.0", deps: deps()]
        end

        defp deps do
          [
            {:nerves, "~> 2.0", runtime: false},
            #{Enum.join(deps, ",\n      ")}
          ]
        end
      end
      """
    end

    defp targets_install(deps) do
      test_project(
        files: %{"mix.exs" => targets_mix_exs(deps), "config/target.exs" => "import Config\n"}
      )
      |> Igniter.compose_task("mdns_lite.install", [])
    end

    defp targets_mix_exs_after(igniter) do
      igniter.rewrite |> Rewrite.source!("mix.exs") |> Rewrite.Source.get(:content)
    end

    test "uses the first targets attribute that another dependency uses" do
      igniter =
        targets_install([
          ~s|{:nerves_system_rpi4, "~> 2.0", runtime: false, targets: :rpi4}|,
          ~s|{:nerves_pack, "~> 0.7", targets: @device_targets}|,
          ~s|{:other, "~> 1.0", targets: @other_targets}|,
          ~s|{:mdns_lite, "~> 1.0"}|
        ])

      assert targets_mix_exs_after(igniter) =~
               ~s|{:mdns_lite, "~> 1.0", targets: @device_targets}|

      # Running it again changes nothing
      igniter
      |> apply_igniter!()
      |> Igniter.compose_task("mdns_lite.install", [])
      |> assert_unchanged("mix.exs")
    end

    test "works for dependencies that only have options" do
      igniter =
        targets_install([
          ~s|{:nerves_pack, "~> 0.7", targets: @device_targets}|,
          ~s|{:mdns_lite, path: "../mdns_lite"}|
        ])

      assert targets_mix_exs_after(igniter) =~
               ~s|{:mdns_lite, path: "../mdns_lite", targets: @device_targets}|
    end

    test "keeps the targets that the dependency already has" do
      targets_install([
        ~s|{:nerves_pack, "~> 0.7", targets: @device_targets}|,
        ~s|{:mdns_lite, "~> 1.0", targets: [:rpi0]}|
      ])
      |> assert_unchanged("mix.exs")
    end

    test "does nothing when no dependency uses a targets attribute" do
      targets_install([
        ~s|{:nerves_system_rpi4, "~> 2.0", runtime: false, targets: :rpi4}|,
        ~s|{:mdns_lite, "~> 1.0"}|
      ])
      |> assert_unchanged("mix.exs")
    end

    test "falls back to @all_targets when it's defined but not used by a dependency" do
      mix_exs = """
      defmodule Test.MixProject do
        use Mix.Project

        @all_targets [:rpi4, :rpi5]

        def project do
          [app: :test, version: "0.1.0", deps: deps()]
        end

        defp deps do
          [
            {:nerves_system_rpi4, "~> 2.0", runtime: false, targets: :rpi4},
            {:mdns_lite, "~> 1.0"}
          ]
        end
      end
      """

      igniter =
        test_project(files: %{"mix.exs" => mix_exs, "config/target.exs" => "import Config\n"})
        |> Igniter.compose_task("mdns_lite.install", [])

      assert targets_mix_exs_after(igniter) =~ ~s|{:mdns_lite, "~> 1.0", targets: @all_targets}|
    end

    test "does nothing when the dependency isn't in mix.exs" do
      targets_install([~s|{:nerves_pack, "~> 0.7", targets: @device_targets}|])
      |> assert_unchanged("mix.exs")
    end
  end

  describe "starting early" do
    test "adds :mdns_lite to Nerves' application_sort init list" do
      target_exs = """
      import Config

      config :nerves, application_sort: [init: [:nerves_runtime]]
      """

      igniter =
        test_project(files: %{"config/target.exs" => target_exs})
        |> Igniter.compose_task("mdns_lite.install", [])

      assert igniter.rewrite
             |> Rewrite.source!("config/target.exs")
             |> Rewrite.Source.get(:content) =~
               "config :nerves, application_sort: [init: [:nerves_runtime, :mdns_lite]]"

      igniter
      |> apply_igniter!()
      |> Igniter.compose_task("mdns_lite.install", [])
      |> assert_unchanged()
    end

    test "leaves a list with :nerves_pack alone and doesn't create one" do
      target_exs = """
      import Config

      config :shoehorn, init: [:nerves_runtime, :nerves_pack]
      """

      igniter =
        test_project(files: %{"config/target.exs" => target_exs})
        |> Igniter.compose_task("mdns_lite.install", [])

      content =
        igniter.rewrite |> Rewrite.source!("config/target.exs") |> Rewrite.Source.get(:content)

      assert content =~ "config :shoehorn, init: [:nerves_runtime, :nerves_pack]"
      refute content =~ "application_sort"
    end
  end
end
