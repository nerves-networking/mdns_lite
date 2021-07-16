defmodule MdnsLite.OptionsTest do
  use ExUnit.Case, async: false

  alias MdnsLite.Options

  # setup do
  #   # Make sure we're starting with known state every time
  #   :sys.replace_state(Options, fn s -> %{s | mdns_services: MapSet.new()} end)

  #   %{
  #     result: %{
  #       name: "SSH Remote Login Protocol",
  #       txt_payload: [""],
  #       port: 22,
  #       priority: 0,
  #       protocol: "ssh",
  #       transport: "tcp",
  #       type: "_ssh._tcp",
  #       weight: 0
  #     },
  #     service: %{
  #       name: "SSH Remote Login Protocol",
  #       protocol: "ssh",
  #       transport: "tcp",
  #       port: 22
  #     }
  #   }
  # end

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
        name: "SSH Remote Login Protocol",
        protocol: "ssh",
        transport: "tcp",
        port: 22
      })

    assert Options.get_services(options) == [
             %MdnsLite.Service{
               name: "SSH Remote Login Protocol",
               port: 22,
               priority: 0,
               protocol: "ssh",
               transport: "tcp",
               txt_payload: [""],
               type: "_ssh._tcp",
               weight: 0
             }
           ]

    options = Options.remove_service_by_name(options, "SSH Remote Login Protocol")
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
end
