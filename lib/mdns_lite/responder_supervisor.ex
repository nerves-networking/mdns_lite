defmodule MdnsLite.ResponderSupervisor do
  use DynamicSupervisor

  @moduledoc false

  alias MdnsLite.Responder

  @spec start_link(any) :: GenServer.on_start()
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @spec start_child(String.t()) :: DynamicSupervisor.on_start_child()
  def start_child(ifname) do
    spec = {MdnsLite.Responder, ifname}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
