defmodule MdnsLiteTest do
  use ExUnit.Case, async: false

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
