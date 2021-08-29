defmodule MdnsLite.Sender do
  @moduledoc false

  import MdnsLite.DNS

  alias MdnsLite.{DNS, Utilities}

  @mdns_ipv4 {224, 0, 0, 251}
  @mdns_port 5353

  @spec send(DNS.dns_query()) :: :ok | {:error, atom()}
  def send(query) do
    message = dns_rec(header: dns_header(id: 0, qr: false, aa: false), qdlist: [query])
    data = :inet_dns.encode(message)

    with {:ok, udp} <-
           :gen_udp.open(
             @mdns_port,
             [:binary, reuseaddr: true, active: false] ++ Utilities.reuse_port_option()
           ),
         :ok <- :gen_udp.send(udp, @mdns_ipv4, @mdns_port, data) do
      :gen_udp.close(udp)
    end
  end
end
