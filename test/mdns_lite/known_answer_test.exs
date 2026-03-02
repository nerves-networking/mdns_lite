# SPDX-FileCopyrightText: 2026 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule MdnsLite.KnownAnswerTest do
  use ExUnit.Case, async: true

  import MdnsLite.DNS

  alias MdnsLite.KnownAnswer

  @our_record dns_rr(
                domain: ~c"nerves-21a5.local",
                type: :a,
                class: :in,
                ttl: 120,
                data: {192, 168, 9, 57}
              )

  test "no suppression when known-answers list is empty" do
    assert KnownAnswer.suppress([@our_record], []) == [@our_record]
  end

  test "suppresses when known-answer TTL > 50% of our TTL" do
    known = dns_rr(@our_record, ttl: 61)
    assert KnownAnswer.suppress([@our_record], [known]) == []
  end

  test "does not suppress when known-answer TTL == 50% of our TTL" do
    known = dns_rr(@our_record, ttl: 60)
    assert KnownAnswer.suppress([@our_record], [known]) == [@our_record]
  end

  test "does not suppress when known-answer TTL < 50% of our TTL" do
    known = dns_rr(@our_record, ttl: 30)
    assert KnownAnswer.suppress([@our_record], [known]) == [@our_record]
  end

  test "does not suppress when domain differs" do
    known = dns_rr(@our_record, domain: ~c"other.local", ttl: 120)
    assert KnownAnswer.suppress([@our_record], [known]) == [@our_record]
  end

  test "does not suppress when type differs" do
    known = dns_rr(@our_record, type: :aaaa, ttl: 120)
    assert KnownAnswer.suppress([@our_record], [known]) == [@our_record]
  end

  test "does not suppress when data differs" do
    known = dns_rr(@our_record, data: {10, 0, 0, 1}, ttl: 120)
    assert KnownAnswer.suppress([@our_record], [known]) == [@our_record]
  end

  test "selectively suppresses matching records" do
    other_record =
      dns_rr(
        domain: ~c"other.local",
        type: :a,
        class: :in,
        ttl: 120,
        data: {10, 0, 0, 1}
      )

    known = dns_rr(@our_record, ttl: 100)

    result = KnownAnswer.suppress([@our_record, other_record], [known])
    assert result == [other_record]
  end
end
