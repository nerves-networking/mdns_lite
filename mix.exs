defmodule MdnsLite.MixProject do
  use Mix.Project

  def project do
    [
      app: :mdns_lite,
      version: "0.1.0",
      elixir: "~> 1.8",
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
      maintainers: ["Peter C Marks"],
      links: "https://github.com/pcmarks/mdns_lite"
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
      {:dns, "~> 2.1"}
    ]
  end
end
