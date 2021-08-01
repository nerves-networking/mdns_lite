defmodule MdnsLite.TableServer do
  use GenServer

  alias MdnsLite.{DNS, IfInfo, Options, Table}

  @moduledoc false

  @spec start_link(Options.t()) :: GenServer.on_start()
  def start_link(opts) when is_struct(opts, Options) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec update_options((Options.t() -> Options.t())) :: :ok
  def update_options(fun) do
    GenServer.call(__MODULE__, {:update_options, fun})
  end

  @spec options() :: Options.t()
  def options() do
    GenServer.call(__MODULE__, :options)
  end

  @spec lookup(DNS.query(), IfInfo.t()) :: [DNS.rr()]
  def lookup(query, if_info) do
    GenServer.call(__MODULE__, {:lookup, query, if_info})
  end

  ##############################################################################
  #   GenServer callbacks
  ##############################################################################
  @impl GenServer
  def init(opts) do
    {:ok, %{options: opts, table: Table.Builder.from_options(opts)}}
  end

  @impl GenServer
  def handle_call(:options, _from, state) do
    {:reply, state.options, state}
  end

  def handle_call({:update_options, fun}, _from, state) do
    new_options = fun.(state.options)

    {:reply, :ok, %{options: new_options, table: Table.Builder.from_options(new_options)}}
  end

  def handle_call({:lookup, query, if_info}, _from, state) do
    rr_list = Table.lookup(state.table, query, if_info)

    {:reply, rr_list, state}
  end
end
