defmodule MdnsLite.CacheTest do
  use ExUnit.Case

  alias MdnsLite.Cache

  import MdnsLite.DNS

  doctest Cache

  @test_a_record dns_rr(
                   class: :in,
                   type: :a,
                   ttl: 120,
                   domain: 'nerves-1234.local',
                   data: {192, 168, 0, 100}
                 )
  @test_aaaa_record dns_rr(
                      class: :in,
                      type: :aaaa,
                      ttl: 120,
                      domain: 'nerves-1234.local',
                      data: {65152, 0, 0, 0, 3297, 21943, 7498, 1443}
                    )

  test "caches A and AAAA records" do
    cache =
      Cache.new()
      |> Cache.insert(0, @test_a_record)
      |> Cache.insert(0, @test_aaaa_record)

    assert Cache.query(cache, dns_query(class: :in, type: :a, domain: 'nerves-1234.local')) == [
             @test_a_record
           ]
  end

  test "expires old records" do
    # Insert a second record right after the first one expires
    cache =
      Cache.new()
      |> Cache.insert(0, @test_a_record)
      |> Cache.insert(120, @test_aaaa_record)

    assert cache == %Cache{records: [@test_aaaa_record], last_gc: 120}
  end

  test "inserting bumps ttl of existing entry" do
    cache =
      Cache.new()
      |> Cache.insert(0, @test_a_record)
      |> Cache.insert(60, @test_a_record)

    assert cache == %Cache{records: [@test_a_record], last_gc: 60}
  end

  test "inserting forces max ttl" do
    cache =
      Cache.new()
      |> Cache.insert(
        0,
        dns_rr(
          class: :in,
          type: :a,
          ttl: 1_200_000,
          domain: 'nerves-1234.local',
          data: {192, 168, 0, 100}
        )
      )

    assert cache == %Cache{
             records: [
               dns_rr(
                 class: :in,
                 type: :a,
                 ttl: 75 * 60,
                 domain: 'nerves-1234.local',
                 data: {192, 168, 0, 100}
               )
             ],
             last_gc: 0
           }
  end

  test "doesn't cache non-mDNS records" do
    cache =
      Cache.new()
      |> Cache.insert(
        0,
        dns_rr(
          class: :in,
          type: :mx,
          domain: 'nerves-1234.local',
          data: {192, 168, 0, 100}
        )
      )

    assert cache == Cache.new()
  end

  test "limits the number of records" do
    final_cache =
      Enum.reduce(1..1000, Cache.new(), fn i, cache ->
        Cache.insert(
          cache,
          0,
          dns_rr(class: :in, type: :a, domain: 'nerves-#{i}.local', data: {1, 2, 3, 4})
        )
      end)

    assert Enum.count(final_cache.records) == 200
  end

  test "can insert many records at a time" do
    cache =
      Cache.new()
      |> Cache.insert_many(0, [@test_a_record, @test_aaaa_record])

    assert cache == %Cache{records: [@test_aaaa_record, @test_a_record], last_gc: 0}
  end
end
