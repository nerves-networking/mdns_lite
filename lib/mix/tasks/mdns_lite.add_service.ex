# SPDX-FileCopyrightText: 2026 Lars Wikman
#
# SPDX-License-Identifier: Apache-2.0
#

defmodule Mix.Tasks.MdnsLite.AddService.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc() do
    "Adds an mDNS service advertisement to your project's mdns_lite config."
  end

  @spec example() :: String.t()
  def example() do
    "mix mdns_lite.add_service --mdns-protocol http --mdns-port 80"
  end

  @spec long_doc() :: String.t()
  def long_doc() do
    """
    #{short_doc()}

    This appends one service to the `:services` list in your
    `config :mdns_lite`. For example, if your device runs a web server on port
    80, the example below adds `%{protocol: "http", transport: "tcp", port: 80}`
    so that the device shows up when browsing for `_http._tcp`.

    The list is looked for in `config/target.exs` and then `config/config.exs`.
    Existing services are never changed or reordered. Nothing is added when the
    list already has a service with the same protocol, transport and port, or
    with the same `:id`, so it is safe to run more than once.

    If there is no `:services` list yet, one is created with only the new
    service. It goes in `config/target.exs` when that file exists and in
    `config/config.exs` otherwise. The `ssh`, `sftp-ssh` and `epmd` services
    that `mix mdns_lite.install` writes are not added by this task.

    The config is left alone when `:services` isn't written as a list (e.g., a
    variable or a function call) or when it is set in `config/runtime.exs`.
    You'll get a notice with the service to add by hand.

    ## Example

    ```bash
    #{example()}
    ```

    ## Options

    * `--mdns-protocol PROTOCOL` - Required. The application protocol without
      the leading underscore. E.g., `http` for `_http._tcp`.
    * `--mdns-port PORT` - Required. The port that the service listens on
      (1-65535).
    * `--mdns-transport TRANSPORT` - `tcp` or `udp`. Defaults to `tcp`.
    * `--mdns-id ID` - An optional `:id` for referring to the service at
      runtime. E.g., `web_server` for `id: :web_server`.
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.MdnsLite.AddService do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task
    alias Igniter.Code.List, as: CodeList
    alias Igniter.Project.Config

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :mdns_lite,
        example: __MODULE__.Docs.example(),
        positional: [],
        schema: [
          mdns_protocol: :string,
          mdns_port: :integer,
          mdns_transport: :string,
          mdns_id: :string
        ],
        defaults: [mdns_transport: "tcp"],
        aliases: [],
        # Checked in igniter/1 so that all problems are reported as issues
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      case validate(igniter.args.options) do
        {:ok, service} -> add_service(igniter, service)
        {:error, messages} -> Enum.reduce(messages, igniter, &Igniter.add_issue(&2, &1))
      end
    end

    # Options --------------------------------------------------------------

    defp validate(options) do
      results = [
        validate_protocol(options[:mdns_protocol]),
        validate_port(options[:mdns_port]),
        validate_transport(options[:mdns_transport]),
        validate_id(options[:mdns_id])
      ]

      case for {:error, message} <- results, do: message do
        [] ->
          [protocol, port, transport, id] = for {:ok, value} <- results, do: value
          {:ok, %{protocol: protocol, port: port, transport: transport, id: id}}

        messages ->
          {:error, messages}
      end
    end

    # Service names are 1 to 15 letters, digits and hyphens (RFC 6335 5.1)
    defp validate_protocol(nil) do
      {:error, "mdns_lite.add_service: --mdns-protocol is required. E.g., --mdns-protocol http"}
    end

    defp validate_protocol(protocol) do
      if byte_size(protocol) <= 15 and protocol =~ ~r/^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$/ do
        {:ok, protocol}
      else
        {:error,
         "mdns_lite.add_service: --mdns-protocol #{inspect(protocol)} is not a service name. " <>
           "Use 1 to 15 letters, digits and hyphens without the leading underscore. E.g., http"}
      end
    end

    defp validate_port(nil) do
      {:error, "mdns_lite.add_service: --mdns-port is required. E.g., --mdns-port 80"}
    end

    defp validate_port(port) when is_integer(port) and port >= 1 and port <= 65_535 do
      {:ok, port}
    end

    defp validate_port(port) do
      {:error,
       "mdns_lite.add_service: --mdns-port #{inspect(port)} is not a port between 1 and 65535"}
    end

    defp validate_transport(transport) when transport in ["tcp", "udp"], do: {:ok, transport}

    defp validate_transport(transport) do
      {:error,
       "mdns_lite.add_service: --mdns-transport #{inspect(transport)} is not supported. " <>
         "Use tcp or udp"}
    end

    defp validate_id(nil), do: {:ok, nil}

    defp validate_id(id) do
      if id =~ ~r/^[a-z][a-zA-Z0-9_]*$/ do
        {:ok, id}
      else
        {:error,
         "mdns_lite.add_service: --mdns-id #{inspect(id)} can't be written as a plain atom. " <>
           "Use letters, digits and underscores starting with a lowercase letter. E.g., web_server"}
      end
    end

    # Config ---------------------------------------------------------------

    defp add_service(igniter, service) do
      runtime = services_ast(igniter, "runtime.exs")
      target = services_ast(igniter, "target.exs")
      config = services_ast(igniter, "config.exs")

      cond do
        runtime != :error ->
          not_added_notice(igniter, service, """
          `config/runtime.exs` sets `:services`, which replaces what the other config files set.
          """)

        target != :error ->
          update_services(igniter, "target.exs", target, service)

        config != :error ->
          update_services(igniter, "config.exs", config, service)

        true ->
          create_services(igniter, service)
      end
    end

    defp update_services(igniter, config_file, :unreachable, service) do
      not_added_notice(igniter, service, """
      `:services` in `config/#{config_file}` is set inside a block or in more than one place.
      """)
    end

    defp update_services(igniter, config_file, {:ok, ast}, service) do
      update_services(igniter, config_file, ast, service)
    end

    defp update_services(igniter, config_file, ast, service) when is_list(ast) do
      case Enum.find_value(ast, &conflict(&1, service)) do
        nil ->
          Config.configure(
            igniter,
            config_file,
            :mdns_lite,
            [:services],
            {:code, Sourceror.parse_string!("[#{service_string(service)}]")},
            updater: &CodeList.append_to_list(&1, service_code(service))
          )

        :equivalent ->
          igniter

        :id_taken ->
          not_added_notice(igniter, service, """
          `config/#{config_file}` already has a different service with `id: :#{service.id}`.
          """)
      end
    end

    defp update_services(igniter, config_file, _ast, service) do
      not_added_notice(igniter, service, """
      `:services` in `config/#{config_file}` isn't written as a list.
      """)
    end

    defp create_services(igniter, service) do
      config_file =
        if Igniter.exists?(igniter, "config/target.exs"), do: "target.exs", else: "config.exs"

      igniter
      |> Config.configure(
        config_file,
        :mdns_lite,
        [:services],
        {:code, Sourceror.parse_string!("[#{service_string(service)}]")}
      )
      |> Igniter.add_notice("""
      mdns_lite: there was no `:services` list in your config, so one was created in
      `config/#{config_file}` with only the #{service_type(service)} service. Run `mix mdns_lite.install`
      if you also want the default configuration with the ssh, sftp-ssh and epmd services.
      """)
    end

    defp not_added_notice(igniter, service, reason) do
      Igniter.add_notice(igniter, """
      mdns_lite: the #{service_type(service)} service was not added.
      #{String.trim(reason)}
      To advertise it, add this to that list:

          #{service_string(service)}
      """)
    end

    # Compare one entry of an existing `:services` list with the new service.
    # Entries that aren't literal maps can't be compared and are skipped.
    defp conflict(entry_ast, service) do
      with {:%{}, _meta, _pairs} <- entry_ast,
           true <- Macro.quoted_literal?(entry_ast),
           {%{} = entry, _binding} <- Code.eval_quoted(entry_ast) do
        cond do
          entry[:port] == service.port and entry_type(entry) == service_type(service) ->
            :equivalent

          same_id?(entry[:id], service.id) ->
            :id_taken

          true ->
            nil
        end
      else
        _ -> nil
      end
    end

    # The new service's id is kept as a string. It's only ever written to the
    # config file.
    defp same_id?(entry_id, id) when is_atom(entry_id) and not is_nil(entry_id) and is_binary(id),
      do: Atom.to_string(entry_id) == id

    defp same_id?(_entry_id, _id), do: false

    defp entry_type(%{type: type}) when is_binary(type), do: type

    defp entry_type(%{protocol: protocol, transport: transport})
         when is_binary(protocol) and is_binary(transport),
         do: "_#{protocol}._#{transport}"

    defp entry_type(_entry), do: nil

    defp service_type(service), do: "_#{service.protocol}._#{service.transport}"

    defp service_code(service), do: Sourceror.parse_string!(service_string(service))

    defp service_string(service) do
      id = if service.id, do: "id: :#{service.id}, ", else: ""

      "%{#{id}protocol: #{inspect(service.protocol)}, " <>
        "transport: #{inspect(service.transport)}, port: #{service.port}}"
    end

    # The value of `:services` as written in a config file. This reads the file
    # without modifying it so that it isn't reformatted when nothing is added.
    #
    # Returns `{:ok, ast}` for the value that `Igniter.Project.Config` would
    # update, `:unreachable` when `:services` is only set somewhere that it
    # wouldn't update (e.g., inside an `if`), and `:error` when it isn't set.
    defp services_ast(igniter, config_file) do
      path = Path.join("config", config_file)

      with true <- Igniter.exists?(igniter, path),
           igniter = Igniter.include_existing_file(igniter, path),
           {:ok, source} <- Rewrite.source(igniter.rewrite, path),
           {:ok, quoted} <- Code.string_to_quoted(Rewrite.Source.get(source, :content)) do
        find_services(quoted)
      else
        _ -> :error
      end
    end

    defp find_services(quoted) do
      with :error <- top_level_services(quoted) do
        if sets_services_anywhere?(quoted), do: :unreachable, else: :error
      end
    end

    # Igniter prefers `config :mdns_lite, :services, value` and then uses the
    # first `config :mdns_lite, key: value` at the top level of the file.
    defp top_level_services(quoted) do
      statements =
        case quoted do
          {:__block__, _, statements} -> statements
          statement -> [statement]
        end

      three_arg =
        Enum.find_value(statements, :error, fn
          {:config, _, [:mdns_lite, :services, value]} -> {:ok, value}
          _other -> false
        end)

      with :error <- three_arg do
        Enum.find_value(statements, :error, fn
          {:config, _, [:mdns_lite, opts]} when is_list(opts) -> keyword_fetch(opts, :services)
          _other -> false
        end)
      end
    end

    defp sets_services_anywhere?(quoted) do
      {_quoted, found?} =
        Macro.prewalk(quoted, false, fn
          {:config, _, [:mdns_lite, :services, _value]} = node, _found? ->
            {node, true}

          {:config, _, [:mdns_lite, opts]} = node, found? when is_list(opts) ->
            {node, found? or keyword_fetch(opts, :services) != :error}

          node, found? ->
            {node, found?}
        end)

      found?
    end

    defp keyword_fetch(opts, key) do
      Enum.find_value(opts, :error, fn
        {^key, value} -> {:ok, value}
        _other -> false
      end)
    end
  end
else
  defmodule Mix.Tasks.MdnsLite.AddService do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @spec run(list()) :: no_return()
    def run(_argv) do
      Mix.shell().error("""
      The task 'mdns_lite.add_service' requires igniter. Please install igniter and try again.

      For more information, see: https://igniter.hexdocs.pm/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
