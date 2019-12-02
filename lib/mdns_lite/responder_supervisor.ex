defmodule MdnsLite.ResponderSupervisor do
  use DynamicSupervisor

  alias MdnsLite.Responder

  @moduledoc false

  @spec start_link(any) :: GenServer.on_start()
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @spec start_child(:inet.ip_address()) :: DynamicSupervisor.on_start_child()
  def start_child(address) do
    spec = {MdnsLite.Responder, address}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def refresh_children(config \\ []) do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(&elem(&1, 1))
    |> Enum.each(&Responder.refresh(&1, config))
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
