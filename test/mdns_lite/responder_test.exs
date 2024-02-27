defmodule MdnsLite.ResponderTest do
  use ExUnit.Case, async: false

  alias MdnsLite.Responder

  test "stopping a nonexistent responder" do
    Responder.stop_server("no_exist", {1, 2, 3, 4})
  end
end
