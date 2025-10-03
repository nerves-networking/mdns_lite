# SPDX-FileCopyrightText: 2021 Frank Hunleth
# SPDX-FileCopyrightText: 2021 Mat Trudel
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule MdnsLite.OptionsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias MdnsLite.Options

  test "default options" do
    {:ok, hostname} = :inet.gethostname()

    expected_if_monitor =
      if Version.match?(System.version(), "~> 1.11"),
        do: MdnsLite.VintageNetMonitor,
        else: MdnsLite.InetMonitor

    assert Options.new() == %Options{
             dot_local_names: ["#{hostname}.local"],
             hosts: ["#{hostname}"],
             services: MapSet.new(),
             ttl: 120,
             instance_name: :unspecified,
             if_monitor: expected_if_monitor
           }
  end

  test "warns on host key" do
    log =
      capture_log(fn ->
        opts = Options.new(host: "old_way")
        assert opts.hosts == ["old_way"]
      end)

    assert log =~ "deprecated"
  end

  test "wraps non-list hosts" do
    opts = Options.new(hosts: "not_list")
    assert opts.hosts == ["not_list"]
  end

  test "hosts lists work" do
    opts = Options.new(hosts: [:hostname, "alias"])
    {:ok, hostname} = :inet.gethostname()
    assert opts.hosts == [to_string(hostname), "alias"]
  end

  test "add and remove a single mdns service" do
    options = Options.new()

    assert Options.get_services(options) == []

    options =
      Options.add_service(options, %{
        id: :ssh_service,
        instance_name: "banana",
        protocol: "ssh",
        transport: "tcp",
        port: 22
      })

    assert Options.get_services(options) == [
             %{
               id: :ssh_service,
               instance_name: "banana",
               port: 22,
               priority: 0,
               txt_payload: [],
               type: "_ssh._tcp",
               weight: 0
             }
           ]

    options = Options.remove_service_by_id(options, :ssh_service)
    assert Options.get_services(options) == []
  end

  test "can set hostname string" do
    host = "howdy"

    options =
      Options.new()
      |> Options.set_hosts([host])

    assert options.hosts == [host]
  end

  test "can set instance name" do
    instance_name = "My Device"

    options =
      Options.new()
      |> Options.set_instance_name(instance_name)

    assert options.instance_name == instance_name
  end

  test "can add hosts" do
    host = "howdy"
    host_alias = "partner"

    options =
      Options.new()
      |> Options.set_hosts([host])
      |> Options.add_host(host_alias)

    assert options.hosts == [host, host_alias]
  end

  test "fails with invalid host" do
    options = Options.new()

    assert_raise RuntimeError, fn -> Options.set_hosts(options, [:wat]) end
  end

  describe "service normalization" do
    test "converts names to ids with warning" do
      log =
        capture_log(fn ->
          {:ok, normalized} =
            Options.normalize_service(%{
              name: "name",
              port: 22,
              type: "_ssh._tcp"
            })

          assert normalized.id == "name"
        end)

      assert log =~ "deprecated"
    end

    test "unspecified id is filled in" do
      {:ok, normalized} =
        Options.normalize_service(%{
          port: 22,
          type: "_ssh._tcp"
        })

      assert normalized.id == :unspecified
    end

    test "port required" do
      assert Options.normalize_service(%{id: :id, type: "_ssh._tcp"}) ==
               {:error, "Specify a port between 1 and 65535 or 0 for no port"}
    end

    test "port can be zero" do
      {:ok, normalized} =
        Options.normalize_service(%{id: :id, port: 0, protocol: "device-info", transport: "tcp"})

      assert normalized.port == 0
    end

    test "converts protocol and transport to a type" do
      {:ok, normalized} =
        Options.normalize_service(%{id: :id, port: 22, protocol: "ssh", transport: "tcp"})

      assert normalized.type == "_ssh._tcp"
    end

    test "type or protocol/transport required" do
      assert Options.normalize_service(%{id: :id, port: 22}) ==
               {:error, "Specify either 1. :protocol and :transport or 2. :type"}
    end
  end
end
