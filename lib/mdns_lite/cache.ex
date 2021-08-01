defmodule MdnsLite.Cache do
  import MdnsLite.DNS

  @type t :: %{DNS.dns_query() => %{rr: [DNS.dns_rr()], expiry: non_neg_integer()}}

  @moduledoc false

  @spec new() :: t()
  def new() do
    %{}
  end

  @doc """
  See if we know about a query already
  """
  @spec lookup(t(), DNS.dns_query()) :: [DNS.dns_rr()]
  def lookup(table, query) do
    case Map.get(table, query) do
      %{rr: rr} -> rr
      _ -> []
    end
  end

  @doc """
  Remove any expired entries
  """
  @spec gc(t(), non_neg_integer()) :: t()
  def gc(table, ticks) do
  end

  @doc """
  Insert a query/response into the cache
  """
  def insert(table, query, rr, expiry) do
  end
end
