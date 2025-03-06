# SPDX-FileCopyrightText: 2021 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule MdnsLiteTest do
  use ExUnit.Case, async: false

  describe "set_hosts/1" do
    test "set hosts to something else" do
      :ok = MdnsLite.set_hosts(["pineapple"])
      assert {:ok, {127, 0, 0, 1}} = MdnsLite.gethostbyname("pineapple.local", 0)
      assert {:error, :nxdomain} = MdnsLite.gethostbyname("nerves.local", 0)

      # Restore the default
      :ok = MdnsLite.set_hosts([:hostname, "nerves"])
    end
  end

  describe "gethostbyname/1" do
    test "query from our configuration" do
      assert {:ok, {127, 0, 0, 1}} = MdnsLite.gethostbyname("nerves.local")

      {:ok, hostname} = :inet.gethostname()
      assert {:ok, {127, 0, 0, 1}} = MdnsLite.gethostbyname(to_string(hostname) <> ".local")
    end

    test "missing host" do
      assert {:error, :nxdomain} = MdnsLite.gethostbyname("definitely-not-on-network.local", 0)
    end
  end
end
