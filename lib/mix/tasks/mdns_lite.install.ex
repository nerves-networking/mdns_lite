defmodule Mix.Tasks.MdnsLite.Install.Docs do
  @moduledoc false

  def short_doc do
    "Installs mdns_lite in your Nerves project."
  end

  def example do
    "mix mdns_lite.install --hostname my-hostname"
  end

  def long_doc do
    """
    #{short_doc()}

    Longer explanation of your task

    ## Example

    ```bash
    #{example()}
    ```

    ## Options

    * `--hostname my-hostname` - Set the initial hostname for the device (will be advertised as "my-hostname.local", defaults to "nerves.local")
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.MdnsLite.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

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
      if Igniter.exists?(igniter, "config/target.exs") do
        igniter
        |> igniter_nerves("target.exs")
      else
        igniter
        |> igniter_nerves("config.exs")
        |> Igniter.add_notice("""
        The defaults for `mix mdns_lite.install` are intended for Nerves projects.  Please visit
        its README at https://hexdocs.pm/mdns_lite/readme.html for an overview of usage.
        """)
      end
    end

    def igniter_nerves(igniter, config_file) do
      igniter
      |> Igniter.Project.Config.configure_new(
        config_file,
        :mdns_lite,
        :host,
        hostname: igniter.args.options[:hostname]
      )
      |> Igniter.Project.Config.configure_new(config_file, :mdns_lite, :ttl, 120)
      |> Igniter.Project.Config.configure_new(
        config_file,
        :mdns_lite,
        :services,
        [
          %{
            protocol: "ssh",
            transport: "tcp",
            port: 22
          },
          %{
            protocol: "sftp-ssh",
            transport: "tcp",
            port: 22
          },
          %{
            protocol: "epmd",
            transport: "tcp",
            port: 4369
          }
        ]
      )
    end
  end
else
  defmodule Mix.Tasks.MdnsLite.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'mdns_lite.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
