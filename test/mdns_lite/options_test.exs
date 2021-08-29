defmodule MdnsLite.OptionsTest do
  use ExUnit.Case, async: false

  alias MdnsLite.Options

  test "default options" do
    {:ok, hostname} = :inet.gethostname()

    assert Options.defaults() == %Options{
             dot_local_names: ["#{hostname}.local"],
             hosts: ["#{hostname}"],
             services: MapSet.new(),
             ttl: 120
           }
  end

  test "add and remove a single mdns service" do
    options = Options.defaults()

    assert Options.get_services(options) == []

    options =
      Options.add_service(options, %{
        id: :ssh_service,
        protocol: "ssh",
        transport: "tcp",
        port: 22
      })

    assert Options.get_services(options) == [
             %{
               id: :ssh_service,
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
      Options.defaults()
      |> Options.set_host(host)

    assert options.hosts == [host]
  end

  test "can add hosts" do
    host = "howdy"
    host_alias = "partner"

    options =
      Options.defaults()
      |> Options.set_host(host)
      |> Options.add_host(host_alias)

    assert options.hosts == [host, host_alias]
  end

  test "fails with invalid host" do
    options = Options.defaults()

    assert_raise RuntimeError, fn -> Options.set_host(options, :wat) end
  end

  import ExUnit.CaptureLog

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
               {:error, "Specify a port"}
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
