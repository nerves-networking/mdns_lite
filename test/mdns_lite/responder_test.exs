# SPDX-FileCopyrightText: 2019 Jon Carstens
# SPDX-FileCopyrightText: 2024 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule MdnsLite.ResponderTest do
  use ExUnit.Case, async: false

  alias MdnsLite.Responder

  test "stopping a nonexistent responder" do
    Responder.stop_server("no_exist", {1, 2, 3, 4})
  end
end
