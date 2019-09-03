defmodule MdnsLite.MixProject do
  use Mix.Project

  @version "0.4.0"

  def project do
    [
      app: :mdns_lite,
      version: @version,
      elixir: "~> 1.9",
      build_embedded: true,
      start_permanent: Mix.env() == :prod,
      docs: docs(),
      description: description(),
      package: package(),
      dialyzer: [
        flags: [:unmatched_returns, :error_handling, :race_conditions, :underspecs],
        ignore_warnings: "dialyzer.ignore_warnings",
        list_unused_filters: true
      ],
      deps: deps()
    ]
  end

  def description do
    "A simple, limited, no frills implementation of an mDNS server"
  end

  def package do
    [
      name: "mdns_lite",
      maintainers: ["Peter C Marks"],
      files: ~w(lib mix.exs README.md LICENSE*
                CHANGELOG* ),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/pcmarks/mdns_lite"}
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {MdnsLite.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dns, "~> 2.1"},
      {:dialyxir, "~> 1.0.0-rc.6", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      extras: ["README.md"],
      source_ref: "v#{@version}",
      source_url: "https://github.com/pcmarks/mdns_lite"
    ]
  end
end
