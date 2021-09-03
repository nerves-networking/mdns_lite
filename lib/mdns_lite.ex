defmodule MdnsLite do
  @moduledoc """
  MdnsLite is a simple, limited, no frills mDNS implementation

  Advertising hostnames and services is generally done using the application
  config.  See `MdnsLite.Options` for documentation.

  To change the advertised hostnames or services at runtime, see `set_host/1`,
  `add_mdns_service/1` and `remove_mdns_service/1`.

  MdnsLite's mDNS record tables and caches can be inspected using
  `MdnsLite.Info` if you're having trouble.

  Finally, check out the MdnsLite `README.md` for more information.
  """

  import MdnsLite.DNS
  require Logger
  alias MdnsLite.{DNS, Options, TableServer}

  @typedoc """
  A user-specified ID for referring to a service

  Atoms are recommended, but binaries are still supported since they were used
  in the past.
  """
  @type service_id() :: atom() | binary()

  @typedoc """
  mDNS service description

  Keys include:

  * `:id` - an atom for referring to this service (only required if you want to
    reference the service at runtime)
  * `:port` - the TCP/UDP port number for the service (required)
  * `:transport` - the transport protocol. E.g., `"tcp"` (specify this and
    `:protocol`, or `:type`) * `:protocol` - the application protocol. E.g.,
    `"ssh"` (specify this and `:transport`, or `:type`)
  * `:type` - the transport/protocol to advertize. E.g., `"_ssh._tcp"` (only
    needed if `:protocol` and `:transport` aren't specified)
  * `:weight` - the service weight. Defaults to `0`. (optional)
  * `:priority` - the service priority. Defaults to `0`. (optional)
  * `:txt_payload` - a list of strings to advertise

  Example:

  ```
  %{id: :my_ssh, port: 22, protocol: "ssh", transport: "tcp"}
  ```
  """
  @type service() :: %{
          :id => service_id(),
          :port => 1..65535,
          optional(:txt_payload) => [String.t()],
          optional(:priority) => 0..255,
          optional(:protocol) => String.t(),
          optional(:transport) => String.t(),
          optional(:type) => String.t(),
          optional(:weight) => 0..255
        }

  @doc """
  Set the list of host names

  `host` can have the value of  `:hostname` in which case the value will be
  replaced with the value of `:inet.gethostname()`, otherwise you can provide a
  string value. You can specify an alias hostname in which case `host` will be
  `["hostname", "alias-example"]`. The second value must be a string. When you
  use an alias, an "A" query can be made to  `alias-example.local` as well as
  to `hostname.local`. This can also be configured at runtime via
  `MdnsLite.set_host/1`:

  ```elixir
  iex> MdnsLite.set_host([:hostname, "nerves"])
  :ok
  ```
  """
  @spec set_host(:hostname | String.t()) :: :ok
  def set_host(host) do
    TableServer.update_options(&Options.set_host(&1, host))
  end

  @doc """
  Start advertising a service

  Services can be added at compile-time via the `:services` key in the `mdns_lite`
  application environment or they can be added at runtime using this function.
  See the `service` type for information on what's needed.

  Example:

  ```elixir
  iex> service = %{
      id: :my_web_server,
      protocol: "http",
      transport: "tcp",
      port: 80
    }
  iex> MdnsLite.add_mdns_service(service)
  :ok
  ```
  """
  @spec add_mdns_service(service()) :: :ok
  def add_mdns_service(service) do
    TableServer.update_options(&Options.add_service(&1, service))
  end

  @doc """
  Stop advertising a service

  Example:

  ```elixir
  iex> MdnsLite.remove_mdns_service(:my_ssh)
  :ok
  ```
  """
  @spec remove_mdns_service(service_id()) :: :ok
  def remove_mdns_service(id) do
    TableServer.update_options(&Options.remove_service_by_id(&1, id))
  end

  @doc """
  Lookup a hostname using mDNS

  The hostname should be a .local name since the query only goes out via mDNS.
  On success, an IP address is returned.
  """
  @spec gethostbyname(String.t()) :: {:ok, :inet.ip_address()} | {:error, any()}
  def gethostbyname(hostname) do
    q = dns_query(class: :in, type: :a, domain: to_charlist(hostname))

    case query(q) do
      %{answer: [first | _]} ->
        ip = first |> dns_rr(:data) |> to_addr()
        {:ok, ip}

      %{answer: []} ->
        {:error, :nxdomain}
    end
  end

  defp to_addr(addr) when is_tuple(addr), do: addr
  defp to_addr(<<a, b, c, d>>), do: {a, b, c, d}

  defp to_addr(<<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>),
    do: {a, b, c, d, e, f, g, h}

  @doc false
  @spec query(DNS.dns_query()) :: %{answer: [DNS.dns_rr()], additional: [DNS.dns_rr()]}
  def query(dns_query() = q) do
    with %{answer: []} <-
           MdnsLite.TableServer.query(q, %MdnsLite.IfInfo{ipv4_address: {127, 0, 0, 1}}),
         %{answer: []} <- MdnsLite.Responder.query_all_caches(q) do
      # Nothing in the cache so make an mDNS request
      send_query(q)
    end
  end

  defp send_query(q) do
    MdnsLite.Responder.multicast_all(q)
    # Wait for updates
    Process.sleep(500)
    MdnsLite.Responder.query_all_caches(q)
  end
end
