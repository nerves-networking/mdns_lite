defmodule MdnsLite.MixProject do
  use Mix.Project

  @version "0.6.6"
  @source_url "https://github.com/nerves-networking/mdns_lite"

  def project do
    [
      app: :mdns_lite,
      version: @version,
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      docs: docs(),
      description: description(),
      package: package(),
      dialyzer: dialyzer(),
      deps: deps(),
      preferred_cli_env: %{
        docs: :docs,
        "hex.publish": :docs,
        "hex.build": :docs,
        credo: :test
      }
    ]
  end

  defp description do
    "A simple, limited, no frills implementation of an mDNS server"
  end

  defp package do
    %{
      files: ~w(lib mix.exs README.md LICENSE*
                CHANGELOG* ),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    }
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: extra_applications(Mix.env()),
      mod: {MdnsLite.Application, []}
    ]
  end

  # Ensure :vintage_net is started when running tests
  def extra_applications(:test), do: [:vintage_net | extra_applications(:default)]
  def extra_applications(_), do: [:logger]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dns, "~> 2.1"},
      {:dialyxir, "~> 1.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.2", only: :test, runtime: false},
      {:ex_doc, "~> 0.22", only: :docs, runtime: false},
      {:vintage_net, "~> 0.7", optional: true}
    ]
  end

  defp dialyzer() do
    [
      flags: [:unmatched_returns, :error_handling, :race_conditions, :underspecs],
      plt_add_apps: [:vintage_net],
      ignore_warnings: "dialyzer.ignore_warnings",
      list_unused_filters: true
    ]
  end

  defp docs do
    [
      extras: ["README.md", "CHANGELOG.md"],
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
