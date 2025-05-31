defmodule MdnsLite.MixProject do
  use Mix.Project

  @version "0.9.0"
  @source_url "https://github.com/nerves-networking/mdns_lite"

  def project do
    [
      app: :mdns_lite,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :dev,
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
    "A simple, no frills mDNS implementation in Elixir"
  end

  defp package do
    %{
      files: [
        "CHANGELOG.md",
        "lib",
        "LICENSES/*",
        "mix.exs",
        "NOTICE",
        "README.md",
        "REUSE.toml",
        "src"
      ],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "REUSE Compliance" =>
          "https://api.reuse.software/info/github.com/elixir-circuits/circuits_gpio"
      }
    }
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MdnsLite.Application, []}
    ]
  end

  defp deps do
    [
      {:igniter, "~> 0.5", optional: true},
      {:dialyxir, "~> 1.1", only: :dev, runtime: false},
      {:credo, "~> 1.2", only: :test, runtime: false},
      {:ex_doc, "~> 0.22", only: :docs, runtime: false},
      {:vintage_net, "~> 0.7", optional: true}
    ]
  end

  defp dialyzer() do
    [
      flags: [:missing_return, :extra_return, :unmatched_returns, :error_handling, :underspecs],
      ignore_warnings: ".dialyzer_ignore.exs",
      plt_add_apps: [:vintage_net, :igniter, :mix, :sourceror]
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
