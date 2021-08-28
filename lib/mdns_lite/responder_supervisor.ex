defmodule MdnsLite.ResponderSupervisor do
  use DynamicSupervisor

  @moduledoc false

  alias MdnsLite.Responder

  @spec start_link(any) :: GenServer.on_start()
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @spec start_child(:inet.ip_address()) :: DynamicSupervisor.on_start_child()
  def start_child(address) do
    DynamicSupervisor.start_child(__MODULE__, {Responder, address})
  end

  @spec stop_child(:inet.ip_address()) :: :ok
  def stop_child(address) do
    Responder.stop_server(address)
  end

  @impl DynamicSupervisor
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
