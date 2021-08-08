defmodule MdnsLite.Cache do
  import MdnsLite.DNS

  @moduledoc """
  Cache for records received over mDNS
  """

  # NOTE: This implementation is not efficient at all. This shouldn't
  #       matter that much since it's not expected that there will be many
  #       records and it won't be called that often.

  @typedoc "Timestamp in seconds (assumed monotonic)"
  @type timestamp() :: non_neg_integer()

  # Don't allow records to last more than 75 minutes
  @max_ttl 75 * 60

  # Only cache a subset of record types
  @cache_types [:a, :aaaa, :ptr, :txt, :srv]

  # Restrict how many records are cached
  @max_records 200

  defstruct last_gc: 0, records: []
  @type t() :: %__MODULE__{last_gc: timestamp(), records: [DNS.dns_rr()]}

  @doc """
  Start an empty cache
  """
  @spec new() :: t()
  def new() do
    %__MODULE__{}
  end

  @doc """
  Run a query against the cache

  IMPORTANT: The cache is not garbage collected, so it can return stale entries.
  Call `gc/2` first to expire old entries.
  """
  @spec query(t(), DNS.dns_query()) :: [DNS.dns_rr()]
  def query(cache, query) do
    MdnsLite.Table.lookup(cache.records, query, %MdnsLite.IfInfo{})
  end

  @doc """
  Remove any expired entries
  """
  @spec gc(t(), timestamp()) :: t()
  def gc(%{last_gc: last_time} = cache, time) when time > last_time do
    seconds_elapsed = time - last_time
    new_records = Enum.reduce(cache.records, [], &gc_record(&1, &2, seconds_elapsed))
    %{cache | records: new_records, last_gc: time}
  end

  def gc(cache, _time), do: cache

  defp gc_record(record, acc, seconds_elapsed) do
    new_ttl = dns_rr(record, :ttl) - seconds_elapsed

    if new_ttl > 0 do
      [dns_rr(record, ttl: new_ttl) | acc]
    else
      acc
    end
  end

  @doc """
  Insert a record into the cache
  """
  @spec insert(t(), timestamp(), DNS.dns_rr()) :: t()
  def insert(cache, time, record) do
    insert_many(cache, time, [record])
  end

  @doc """
  Insert several record into the cache
  """
  @spec insert_many(t(), timestamp(), [DNS.dns_rr()]) :: t()
  def insert_many(cache, time, records) do
    records = records |> Enum.filter(&valid_record?/1) |> Enum.map(&cap_ttl/1)

    if records != [] do
      cache
      |> gc(time)
      |> drop_if_full(Enum.count(records))
      |> do_insert_many(records)
    else
      cache
    end
  end

  defp do_insert_many(cache, records) do
    Enum.reduce(records, cache, &do_insert(&2, &1))
  end

  defp do_insert(cache, record) do
    %{cache | records: insert_or_update(cache.records, record, [])}
  end

  defp insert_or_update([], new_rr, result) do
    [new_rr | result]
  end

  defp insert_or_update(
         [dns_rr(class: c, type: t, domain: d) | rest],
         dns_rr(class: c, type: t, domain: d) = new_rr,
         result
       ) do
    [new_rr | rest] ++ result
  end

  defp insert_or_update([rr | rest], new_rr, result) do
    insert_or_update(rest, new_rr, [rr | result])
  end

  defp cap_ttl(dns_rr(ttl: ttl) = record) when ttl > @max_ttl do
    dns_rr(record, ttl: @max_ttl)
  end

  defp cap_ttl(record), do: record

  defp valid_record?(dns_rr(class: :in, type: t)) when t in @cache_types, do: true
  defp valid_record?(_other), do: false

  defp drop_if_full(cache, count) do
    %{cache | records: Enum.take(cache.records, @max_records - count)}
  end
end
