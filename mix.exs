defmodule TinyElixirStripe.MixProject do
  use Mix.Project

  def project do
    [
      app: :tiny_elixir_stripe,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:req, "~> 0.5.0"},
      {:spark, "~> 2.3"},
      {:igniter, "~> 0.6", optional: true},
      {:phoenix, "~> 1.7", optional: true},
      {:usage_rules, "~> 0.1"}
    ]
  end
end
