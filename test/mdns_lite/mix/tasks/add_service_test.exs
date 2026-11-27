# SPDX-FileCopyrightText: 2026 Lars Wikman
#
# SPDX-License-Identifier: Apache-2.0
#

defmodule MdnsLite.Mix.Tasks.AddServiceTest do
  use ExUnit.Case, async: true
  import Igniter.Test

  alias Mix.Tasks.MdnsLite.Install

  @http ["--mdns-protocol", "http", "--mdns-port", "80"]

  # What `mix nerves.new` generates
  @nerves_new_target_exs """
  import Config

  config :mdns_lite,
    # The `hosts` key specifies what hostnames mdns_lite advertises.
    hosts: [:hostname, "nerves"],
    ttl: 120,

    # Advertise the following services over mDNS.
    services: [
      %{
        protocol: "ssh",
        transport: "tcp",
        port: 22
      },
      %{
        protocol: "sftp-ssh",
        transport: "tcp",
        port: 22
      },
      %{
        protocol: "epmd",
        transport: "tcp",
        port: 4369
      }
    ]
  """

  defp content(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end

  defp mdns_lite_options(igniter, path) do
    config = Config.Reader.eval!(path, content(igniter, path))
    MdnsLite.Options.new(config[:mdns_lite])
  end

  defp service_types_and_ports(options) do
    options |> MdnsLite.Options.get_services() |> Enum.map(&{&1.type, &1.port}) |> Enum.sort()
  end

  test "appends to the services that mdns_lite.install writes" do
    igniter =
      test_project(files: %{"config/target.exs" => "import Config\n"})
      |> Igniter.compose_task("mdns_lite.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("mdns_lite.add_service", @http)
      |> assert_has_patch("config/target.exs", """
        - |    %{protocol: "epmd", port: 4369, transport: "tcp"}
        + |    %{protocol: "epmd", port: 4369, transport: "tcp"},
        + |    %{protocol: "http", transport: "tcp", port: 80}
      """)
      |> assert_unchanged("config/config.exs")
      |> apply_igniter!()

    assert igniter.notices == []

    assert service_types_and_ports(mdns_lite_options(igniter, "config/target.exs")) == [
             {"_epmd._tcp", 4369},
             {"_http._tcp", 80},
             {"_sftp-ssh._tcp", 22},
             {"_ssh._tcp", 22}
           ]
  end

  test "appends to the services in a mix nerves.new target.exs" do
    igniter =
      test_project(files: %{"config/target.exs" => @nerves_new_target_exs})
      |> Igniter.compose_task("mdns_lite.add_service", @http)
      |> assert_has_patch("config/target.exs", """
        - |    }
        + |    },
        + |    %{protocol: "http", transport: "tcp", port: 80}
      """)
      |> apply_igniter!()

    # Everything else is as it was
    [before_services, after_services] = String.split(@nerves_new_target_exs, "    }\n  ]\n")

    assert content(igniter, "config/target.exs") ==
             before_services <>
               ~s(    },\n    %{protocol: "http", transport: "tcp", port: 80}\n  ]\n) <>
               after_services
  end

  test "appends to services in config.exs when that's where they are" do
    test_project(
      files: %{
        "config/config.exs" => """
        import Config

        config :mdns_lite, services: [%{protocol: "ssh", transport: "tcp", port: 22}]

        import_config "target.exs"
        """,
        "config/target.exs" => "import Config\n"
      }
    )
    |> Igniter.compose_task("mdns_lite.add_service", @http)
    |> assert_has_patch("config/config.exs", """
      - |config :mdns_lite, services: [%{protocol: "ssh", transport: "tcp", port: 22}]
      + |config :mdns_lite,
      + |  services: [
      + |    %{protocol: "ssh", transport: "tcp", port: 22},
      + |    %{protocol: "http", transport: "tcp", port: 80}
      + |  ]
    """)
    |> assert_unchanged("config/target.exs")
  end

  test "appends to an empty list and to the three argument form" do
    test_project(
      files: %{"config/target.exs" => "import Config\n\nconfig :mdns_lite, services: []\n"}
    )
    |> Igniter.compose_task("mdns_lite.add_service", @http)
    |> assert_has_patch("config/target.exs", """
      - |config :mdns_lite, services: []
      + |config :mdns_lite, services: [%{protocol: "http", transport: "tcp", port: 80}]
    """)

    test_project(
      files: %{
        "config/target.exs" => """
        import Config

        config :mdns_lite, hosts: [:hostname]
        config :mdns_lite, :services, [%{protocol: "ssh", transport: "tcp", port: 22}]
        """
      }
    )
    |> Igniter.compose_task("mdns_lite.add_service", @http)
    |> assert_has_patch("config/target.exs", """
      + |config :mdns_lite, :services, [
      + |  %{protocol: "ssh", transport: "tcp", port: 22},
      + |  %{protocol: "http", transport: "tcp", port: 80}
      + |]
    """)
  end

  describe "missing services key" do
    test "creates the list with only the new service in target.exs" do
      igniter =
        test_project(
          files: %{
            "config/target.exs" => """
            import Config

            config :mdns_lite, hosts: [:hostname, "nerves"]
            """
          }
        )
        |> Igniter.compose_task("mdns_lite.add_service", @http)
        |> assert_has_patch("config/target.exs", """
          - |config :mdns_lite, hosts: [:hostname, "nerves"]
          + |config :mdns_lite,
          + |  hosts: [:hostname, "nerves"],
          + |  services: [%{protocol: "http", transport: "tcp", port: 80}]
        """)
        |> assert_has_notice("""
        mdns_lite: there was no `:services` list in your config, so one was created in
        `config/target.exs` with only the _http._tcp service. Run `mix mdns_lite.install`
        if you also want the default configuration with the ssh, sftp-ssh and epmd services.
        """)
        |> apply_igniter!()

      refute content(igniter, "config/target.exs") =~ "ssh"
    end

    test "uses config.exs when there's no target.exs" do
      test_project(files: %{"config/config.exs" => "import Config\n"})
      |> Igniter.compose_task("mdns_lite.add_service", @http)
      |> assert_has_patch("config/config.exs", """
        + |config :mdns_lite, services: [%{protocol: "http", transport: "tcp", port: 80}]
      """)
      |> assert_has_notice(&(&1 =~ "one was created in\n`config/config.exs`"))
    end

    test "is idempotent" do
      test_project(files: %{"config/target.exs" => "import Config\n"})
      |> Igniter.compose_task("mdns_lite.add_service", @http)
      |> apply_igniter!()
      |> Igniter.compose_task("mdns_lite.add_service", @http)
      |> assert_unchanged()
    end
  end

  describe "services that can't be updated" do
    defp assert_not_added(files, reason) do
      igniter =
        test_project(files: files)
        |> Igniter.compose_task("mdns_lite.add_service", @http)
        |> assert_unchanged()
        |> assert_has_notice("""
        mdns_lite: the _http._tcp service was not added.
        #{reason}
        To advertise it, add this to that list:

            %{protocol: "http", transport: "tcp", port: 80}
        """)

      assert igniter.issues == []
    end

    test "leaves a variable alone" do
      assert_not_added(
        %{
          "config/target.exs" => """
          import Config

          services = [%{protocol: "ssh", transport: "tcp", port: 22}]

          config :mdns_lite, services: services
          """
        },
        "`:services` in `config/target.exs` isn't written as a list."
      )
    end

    test "leaves an expression alone" do
      assert_not_added(
        %{
          "config/config.exs" => """
          import Config

          config :mdns_lite,
                 :services,
                 Enum.map([22, 2222], &%{protocol: "ssh", transport: "tcp", port: &1})
          """
        },
        "`:services` in `config/config.exs` isn't written as a list."
      )
    end

    test "leaves services that are set inside a block alone" do
      assert_not_added(
        %{
          "config/target.exs" => """
          import Config

          if Mix.target() == :rpi4 do
            config :mdns_lite, services: [%{protocol: "ssh", transport: "tcp", port: 22}]
          end
          """
        },
        "`:services` in `config/target.exs` is set inside a block or in more than one place."
      )
    end

    test "leaves services alone when a second config call sets them" do
      assert_not_added(
        %{
          "config/target.exs" => """
          import Config

          config :mdns_lite, hosts: [:hostname]
          config :mdns_lite, services: [%{protocol: "ssh", transport: "tcp", port: 22}]
          """
        },
        "`:services` in `config/target.exs` is set inside a block or in more than one place."
      )
    end

    test "leaves everything alone when runtime.exs sets services" do
      assert_not_added(
        %{
          "config/target.exs" => @nerves_new_target_exs,
          "config/runtime.exs" => """
          import Config

          config :mdns_lite, services: [%{protocol: "ssh", transport: "tcp", port: 22}]
          """
        },
        "`config/runtime.exs` sets `:services`, which replaces what the other config files set."
      )
    end
  end

  describe "idempotency" do
    test "running twice changes nothing the second time" do
      test_project(files: %{"config/target.exs" => @nerves_new_target_exs})
      |> Igniter.compose_task("mdns_lite.add_service", @http ++ ["--mdns-id", "web_server"])
      |> apply_igniter!()
      |> Igniter.compose_task("mdns_lite.add_service", @http ++ ["--mdns-id", "web_server"])
      |> assert_unchanged()
    end

    # The file isn't formatted like `mix format` would and has the keys in a
    # different order.
    @unformatted_target_exs """
    import Config

    config :mdns_lite,
      services: [
        %{port: 80,   transport: "tcp", protocol: "http"},
        %{id: :ssh_daemon, type: "_ssh._tcp", port: 22},
        %{id: :web_server, protocol: "http", transport: "tcp", port: 8080, txt_payload: ["a=b"]}
      ],
      hosts:    [:hostname]
    """

    test "an equivalent service leaves the file exactly as it was" do
      igniter =
        test_project(files: %{"config/target.exs" => @unformatted_target_exs})
        |> Igniter.compose_task("mdns_lite.add_service", @http)
        |> assert_unchanged()

      assert content(igniter, "config/target.exs") == @unformatted_target_exs
      assert igniter.notices == []
    end

    test "an equivalent service with another id isn't added" do
      test_project(files: %{"config/target.exs" => @unformatted_target_exs})
      |> Igniter.compose_task("mdns_lite.add_service", @http ++ ["--mdns-id", "my_http"])
      |> assert_unchanged()
    end

    test "an equivalent service that uses :type isn't added" do
      test_project(files: %{"config/target.exs" => @unformatted_target_exs})
      |> Igniter.compose_task("mdns_lite.add_service", [
        "--mdns-protocol",
        "ssh",
        "--mdns-port",
        "22"
      ])
      |> assert_unchanged()
    end

    test "an id that's used by a different service isn't added or changed" do
      igniter =
        test_project(files: %{"config/target.exs" => @unformatted_target_exs})
        |> Igniter.compose_task("mdns_lite.add_service", [
          "--mdns-protocol",
          "https",
          "--mdns-port",
          "443",
          "--mdns-id",
          "web_server"
        ])
        |> assert_unchanged()
        |> assert_has_notice("""
        mdns_lite: the _https._tcp service was not added.
        `config/target.exs` already has a different service with `id: :web_server`.
        To advertise it, add this to that list:

            %{id: :web_server, protocol: "https", transport: "tcp", port: 443}
        """)

      assert content(igniter, "config/target.exs") == @unformatted_target_exs
    end

    test "the same protocol on another port or transport is added" do
      igniter =
        test_project(files: %{"config/target.exs" => @unformatted_target_exs})
        |> Igniter.compose_task("mdns_lite.add_service", [
          "--mdns-protocol",
          "http",
          "--mdns-port",
          "8000"
        ])
        |> apply_igniter!()
        |> Igniter.compose_task("mdns_lite.add_service", @http ++ ["--mdns-transport", "udp"])
        |> apply_igniter!()

      assert service_types_and_ports(mdns_lite_options(igniter, "config/target.exs")) == [
               {"_http._tcp", 80},
               {"_http._tcp", 8000},
               {"_http._tcp", 8080},
               {"_http._udp", 80},
               {"_ssh._tcp", 22}
             ]
    end
  end

  describe "options" do
    defp add_service_to_empty_list(argv) do
      test_project(
        files: %{"config/target.exs" => "import Config\n\nconfig :mdns_lite, services: []\n"}
      )
      |> Igniter.compose_task("mdns_lite.add_service", argv)
    end

    test "--mdns-protocol and --mdns-port" do
      add_service_to_empty_list(["--mdns-protocol", "sftp-ssh", "--mdns-port", "2222"])
      |> assert_has_patch("config/target.exs", """
        + |config :mdns_lite, services: [%{protocol: "sftp-ssh", transport: "tcp", port: 2222}]
      """)
    end

    test "--mdns-transport" do
      add_service_to_empty_list([
        "--mdns-protocol",
        "osc",
        "--mdns-port",
        "8000",
        "--mdns-transport",
        "udp"
      ])
      |> assert_has_patch("config/target.exs", """
        + |config :mdns_lite, services: [%{protocol: "osc", transport: "udp", port: 8000}]
      """)
    end

    test "--mdns-id" do
      igniter =
        add_service_to_empty_list(@http ++ ["--mdns-id", "web_server"])
        |> assert_has_patch("config/target.exs", """
          + |config :mdns_lite, services: [%{id: :web_server, protocol: "http", transport: "tcp", port: 80}]
        """)
        |> apply_igniter!()

      assert [%{id: :web_server, type: "_http._tcp", port: 80}] =
               MdnsLite.Options.get_services(mdns_lite_options(igniter, "config/target.exs"))
    end
  end

  describe "invalid input" do
    defp assert_rejected(argv, message) do
      igniter =
        test_project(files: %{"config/target.exs" => @nerves_new_target_exs})
        |> Igniter.compose_task("mdns_lite.add_service", argv)
        |> assert_unchanged()

      assert Enum.any?(igniter.issues, &(&1 =~ message)),
             "expected an issue with #{inspect(message)} in #{inspect(igniter.issues)}"

      igniter
    end

    test "protocol and port are required" do
      igniter = assert_rejected([], "--mdns-protocol is required")
      assert Enum.any?(igniter.issues, &(&1 =~ "--mdns-port is required"))

      assert_rejected(["--mdns-port", "80"], "--mdns-protocol is required")
      assert_rejected(["--mdns-protocol", "http"], "--mdns-port is required")
    end

    test "port must be between 1 and 65535" do
      for port <- ["0", "65536", "-1"] do
        assert_rejected(
          ["--mdns-protocol", "http", "--mdns-port", port],
          "--mdns-port #{port} is not a port between 1 and 65535"
        )
      end
    end

    test "a port that isn't a number is rejected when parsing the options" do
      assert_raise OptionParser.ParseError, ~r/--mdns-port/, fn ->
        test_project()
        |> Igniter.compose_task("mdns_lite.add_service", [
          "--mdns-protocol",
          "http",
          "--mdns-port",
          "www"
        ])
      end
    end

    test "protocol must be a service name without the underscore" do
      for protocol <- ["_http", "_http._tcp", "http tcp", "http-", "a-very-long-service-name"] do
        assert_rejected(
          ["--mdns-protocol", protocol, "--mdns-port", "80"],
          "--mdns-protocol #{inspect(protocol)} is not a service name"
        )
      end
    end

    test "transport must be tcp or udp" do
      assert_rejected(
        @http ++ ["--mdns-transport", "sctp"],
        ~s(--mdns-transport "sctp" is not supported)
      )
    end

    test "id must be a plain atom" do
      for id <- ["Web", "web server", "1web", "web-server"] do
        assert_rejected(
          @http ++ ["--mdns-id", id],
          "--mdns-id #{inspect(id)} can't be written as a plain atom"
        )
      end
    end
  end

  test "mdns_lite.install doesn't run this task" do
    refute "mdns_lite.add_service" in Install.info([], nil).composes
  end
end
