defmodule MdnsLite.MixProject do
  use Mix.Project

  def project do
    [
      app: :mdns_lite,
      version: "0.1.0",
      elixir: "~> 1.8",
      build_permanent: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      docs: [extras: ["README.md"]],
      description: description(),
      package: package(),
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
      files: ~w(lib priv .formatter.exs mix.exs README* readme* LICENSE*
                license* CHANGELOG* changelog* src),
      licenses: ["Apache-2.0"],
      links: "https://github.com/pcmarks/mdns_lite"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dns, "~> 2.1"},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false}
    ]
  end
end
