defmodule MdnsLite.MixProject do
  use Mix.Project

  @version "0.6.2"

  def project do
    [
      app: :mdns_lite,
      version: @version,
      elixir: "~> 1.7",
      build_embedded: true,
      start_permanent: Mix.env() == :prod,
      docs: docs(),
      description: description(),
      package: package(),
      dialyzer: [
        flags: [:unmatched_returns, :error_handling, :race_conditions, :underspecs],
        plt_add_apps: [:vintage_net],
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
      {:dialyxir, "~> 1.0.0-rc.6", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:vintage_net, "~> 0.7", optional: true}
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
