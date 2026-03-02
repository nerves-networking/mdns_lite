# SPDX-FileCopyrightText: 2026 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule MdnsLite.KnownAnswer do
  @moduledoc false

  # Known-answer suppression per RFC 6762 §7.1
  #
  # When a querier includes known-answer records in the answer section of a
  # query, the responder should suppress answers where the known-answer has
  # a TTL greater than half of our TTL.

  import MdnsLite.DNS

  alias MdnsLite.DNS

  @doc """
  Filter out answers that are already known by the querier.

  An answer is suppressed if the querier's known-answer has the same
  domain/type/class/data and a TTL greater than half of our record's TTL.
  """
  @spec suppress([DNS.dns_rr()], [DNS.dns_rr()]) :: [DNS.dns_rr()]
  def suppress(our_answers, known_answers) do
    Enum.reject(our_answers, fn our_rr ->
      Enum.any?(known_answers, fn ka ->
        same_record?(our_rr, ka) and dns_rr(ka, :ttl) > div(dns_rr(our_rr, :ttl), 2)
      end)
    end)
  end

  defp same_record?(a, b) do
    dns_rr(a, :domain) == dns_rr(b, :domain) and
      dns_rr(a, :type) == dns_rr(b, :type) and
      dns_rr(a, :class) == dns_rr(b, :class) and
      dns_rr(a, :data) == dns_rr(b, :data)
  end
end
