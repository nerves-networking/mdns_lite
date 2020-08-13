defmodule MdnsLite.ResponderTest do
  use ExUnit.Case, async: false

  alias MdnsLite.{Responder, ResponderSupervisor}

  test "can refresh" do
    {:ok, responder} = ResponderSupervisor.start_child({127, 1, 1, 6})

    some_service = %{
      name: "My Service",
      txt_payload: [""],
      port: 1234,
      priority: 0,
      protocol: "nunya",
      transport: "tcp",
      type: "_nunya._tcp",
      weight: 0
    }

    new_host = "whoder"

    state = :sys.get_state(responder)

    # Make sure data not already in responder state
    refute state.instance_name == new_host
    refute some_service in state.services

    Responder.refresh(responder, mdns_services: [some_service], mdns_config: %{host: new_host})

    new_state = :sys.get_state(responder)

    assert new_state.instance_name == new_host
    assert some_service in new_state.services
  end
end
