# SPDX-FileCopyrightText: 2025 Authors of https://github.com/ash-project/igniter
# SPDX-FileCopyrightText: 2025 Lee Nussbaum
# SPDX-FileCopyrightText: 2026 Frank Hunleth
# SPDX-FileCopyrightText: 2026 Lars Wikman
#
# SPDX-License-Identifier: Apache-2.0
#

defmodule Mix.Tasks.MdnsLite.Install.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc() do
    "Installs mdns_lite in your Nerves project."
  end

  @spec example() :: String.t()
  def example() do
    "mix igniter.install mdns_lite --hostname my-hostname"
  end

  @spec long_doc() :: String.t()
  def long_doc() do
    """
    #{short_doc()}

    This adds the same `:mdns_lite` configuration that `mix nerves.new` generates:
    the device advertises `<hostname>.local` plus a fixed alias (`nerves.local`
    by default), and the `ssh`, `sftp-ssh` and `epmd` services.

    The configuration is written to `config/target.exs` when that file exists
    (a Nerves project) and to `config/config.exs` otherwise. Keys that are
    already set in `config/config.exs`, `config/target.exs` or
    `config/runtime.exs` are left alone, so it is safe to run more than once.

    ## Example

    ```bash
    #{example()}
    ```

    ## Options

    * `--hostname my-hostname` - An additional hostname to advertise next to
      the device's own hostname. `my-hostname` is advertised as
      "my-hostname.local". Defaults to "nerves" ("nerves.local"). If more than
      one device is on the network, give each a different name or delete the
      alias from the generated `:hosts` list.
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.MdnsLite.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task
    alias Igniter.Code.Common
    alias Igniter.Code.List, as: CodeList
    alias Igniter.Project.Config
    alias Igniter.Project.Deps

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        # Groups allow for overlapping arguments for tasks by the same author
        # See the generators guide for more.
        group: :mdns_lite,
        # *other* dependencies to add
        # i.e `{:foo, "~> 2.0"}`
        adds_deps: [],
        # *other* dependencies to add and call their associated installers, if they exist
        # i.e `{:foo, "~> 2.0"}`
        installs: [],
        # An example invocation
        example: __MODULE__.Docs.example(),
        # A list of environments that this should be installed in.
        only: nil,
        # a list of positional arguments, i.e `[:file]`
        positional: [],
        # Other tasks your task composes using `Igniter.compose_task`, passing in the CLI argv
        # This ensures your option schema includes options from nested tasks
        composes: [],
        # `OptionParser` schema
        schema: [hostname: :string],
        # Default values for the options in the `schema`
        defaults: [hostname: "nerves"],
        # CLI aliases
        aliases: [],
        # A list of options in the schema that are required
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter = igniter |> restrict_dep_to_targets() |> start_early()

      if Igniter.exists?(igniter, "config/target.exs") do
        igniter
        |> igniter_nerves("target.exs")
      else
        igniter
        |> igniter_nerves("config.exs")
        |> Igniter.add_notice("""
        The defaults for `mix mdns_lite.install` are intended for Nerves projects.  Please visit
        its README at https://mdns-lite.hexdocs.pm/readme.html for an overview of usage.
        """)
      end
    end

    @spec igniter_nerves(Igniter.t(), String.t()) :: Igniter.t()
    def igniter_nerves(igniter, config_file) do
      igniter
      |> configure_hosts(config_file)
      |> configure_unless_set(config_file, :ttl, 120)
      |> configure_unless_set(
        config_file,
        :services,
        {:code,
         Sourceror.parse_string!("""
           [
             %{protocol: "ssh", port: 22, transport: "tcp"},
             %{protocol: "sftp-ssh", port: 22, transport: "tcp"},
             %{protocol: "epmd", port: 4369, transport: "tcp"}
           ]
         """)}
      )
    end

    # `:hostname` advertises the device's own hostname (nerves-<serial> on the
    # official Nerves systems). The string is a fixed alias for convenience.
    defp configure_hosts(igniter, config_file) do
      if configured?(igniter, config_file, :host) do
        # `:host` is the deprecated name for `:hosts` and takes precedence over
        # it, so adding `:hosts` would have no effect.
        Igniter.add_notice(igniter, """
        mdns_lite: your config sets the deprecated `:host` option, so `:hosts` was not added.
        Rename `host:` to `hosts:` in your `config :mdns_lite` to remove the deprecation warning.
        """)
      else
        configure_unless_set(igniter, config_file, :hosts, [
          :hostname,
          igniter.args.options[:hostname]
        ])
      end
    end

    defp configure_unless_set(igniter, config_file, key, value) do
      if configured?(igniter, config_file, key) do
        igniter
      else
        Config.configure_new(igniter, config_file, :mdns_lite, [key], value)
      end
    end

    # target.exs is imported by config.exs, and runtime.exs overrides both, so a
    # value in any of them counts as the user's choice.
    defp configured?(igniter, config_file, key) do
      [config_file, "config.exs", "target.exs", "runtime.exs"]
      |> Enum.uniq()
      |> Enum.any?(&Config.configures_key?(igniter, &1, :mdns_lite, key))
    end

    # Nerves projects have a list of applications that are started before the
    # project's own application. Having mDNS in it keeps a device findable
    # when that application fails to start. This only extends a list that the
    # project already has. `:nerves_pack` in it covers `:mdns_lite`.
    defp start_early(igniter) do
      for {config_app, key_path} <- [{:nerves, [:application_sort, :init]}, {:shoehorn, [:init]}],
          file = init_list_file(igniter, config_app, key_path),
          reduce: igniter do
        igniter ->
          Config.configure(igniter, file, config_app, key_path, [:mdns_lite],
            updater: &append_to_init_list/1
          )
      end
    end

    defp init_list_file(igniter, config_app, key_path) do
      Enum.find(["target.exs", "config.exs"], fn file ->
        Igniter.exists?(igniter, Path.join("config", file)) and
          Config.configures_key?(igniter, file, config_app, key_path)
      end)
    end

    defp append_to_init_list(zipper) do
      case Common.within(zipper, &append_mdns_lite/1) do
        {:ok, zipper} -> {:ok, zipper}
        :error -> {:ok, zipper}
      end
    end

    defp append_mdns_lite(list) do
      cond do
        not CodeList.list?(list) -> :error
        in_list?(list, :nerves_pack) or in_list?(list, :mdns_lite) -> :error
        true -> CodeList.append_to_list(list, :mdns_lite)
      end
    end

    defp in_list?(list, app) do
      CodeList.find_list_item_index(list, &Common.nodes_equal?(&1, app)) !=
        nil
    end

    # mix.exs --------------------------------------------------------------

    # mdns_lite answers mDNS queries on the network that it runs on.
    # Nerves projects keep such dependencies off the host with a `:targets`
    # option that refers to a module attribute. E.g.,
    # `{:nerves_pack, "~> 0.7", targets: @all_targets}`. When the project has
    # one and :mdns_lite is listed in mix.exs without `:targets`, it gets
    # the first such attribute too. Nothing is changed otherwise, like when
    # :mdns_lite is brought in by :nerves_pack.
    defp restrict_dep_to_targets(igniter) do
      with {:ok, declaration} when is_binary(declaration) <-
             Deps.get_dep(igniter, :mdns_lite),
           {:ok, dep} <- Code.string_to_quoted(declaration),
           false <- has_targets_option?(dep),
           {:ok, quoted} <- Code.string_to_quoted(mix_exs(igniter)),
           attribute when is_atom(attribute) and not is_nil(attribute) <-
             first_targets_attribute(quoted) do
        Deps.set_dep_option(
          igniter,
          :mdns_lite,
          :targets,
          {:@, [], [{attribute, [], nil}]}
        )
      else
        _ -> igniter
      end
    end

    defp mix_exs(igniter) do
      igniter = Igniter.include_existing_file(igniter, "mix.exs")

      case Rewrite.source(igniter.rewrite, "mix.exs") do
        {:ok, source} -> Rewrite.Source.get(source, :content)
        _ -> ""
      end
    end

    defp has_targets_option?(quoted) do
      {_quoted, found?} =
        Macro.prewalk(quoted, false, fn
          {:targets, _value} = node, _found? -> {node, true}
          node, found? -> {node, found?}
        end)

      found?
    end

    # The name of the module attribute in the first `targets: @attribute`. If
    # no dependency has one, `@all_targets` is used when mix.exs defines it.
    # That's the attribute that Nerves projects list their targets in.
    defp first_targets_attribute(quoted) do
      {_quoted, {used, all_targets?}} =
        Macro.prewalk(quoted, {nil, false}, fn
          {:targets, {:@, _, [{name, _, context}]}} = node, {nil, all_targets?}
          when is_atom(name) and is_atom(context) ->
            {node, {name, all_targets?}}

          {:@, _, [{:all_targets, _, [_value]}]} = node, {used, _all_targets?} ->
            {node, {used, true}}

          node, acc ->
            {node, acc}
        end)

      used || if(all_targets?, do: :all_targets)
    end
  end
else
  defmodule Mix.Tasks.MdnsLite.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @spec run(list()) :: no_return()
    def run(_argv) do
      Mix.shell().error("""
      The task 'mdns_lite.install' requires igniter. Please install igniter and try again.

      For more information, see: https://igniter.hexdocs.pm/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
