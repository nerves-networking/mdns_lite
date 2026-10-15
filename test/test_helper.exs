# SPDX-FileCopyrightText: 2019 Peter C. Marks
#
# SPDX-License-Identifier: Apache-2.0
#

defmodule TestUtilities do
  @doc """
  Return list of inet families that are available

  Returns `[:inet, :inet6]` are most systems
  """
  @spec available_families() :: [:inet | :inet6]
  def available_families() do
    {:ok, ifaddrs} = :net.getifaddrs()

    localhost?(ifaddrs, :inet, {127, 0, 0, 1}) ++
      localhost?(ifaddrs, :inet6, {0, 0, 0, 0, 0, 0, 0, 1})
  end

  defp localhost?(ifaddrs, family, addr) do
    if Enum.any?(ifaddrs, &match?(%{addr: %{addr: ^addr}}, &1)), do: [family], else: []
  end
end

ExUnit.start()
