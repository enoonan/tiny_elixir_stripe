defmodule TinyElixirStripe.MixProject do
  use Mix.Project

  @version "0.0.2"
  @source_url "https://github.com/enoonan/tiny-elixir-stripe"

  def project do
    [
      app: :tiny_elixir_stripe,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Hex
      description: description(),
      package: package(),

      # Docs
      name: "TinyElixirStripe",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs()
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
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:req, "~> 0.5.0"},
      {:spark, "~> 2.3"},
      {:igniter, "~> 0.6", optional: true},
      {:phoenix, "~> 1.7", optional: true},
      {:usage_rules, "~> 0.1"}
    ]
  end

  defp description do
    """
    A minimal Stripe SDK for Elixir with webhook handling, built on Req and Spark.
    Provides a simple API client and declarative DSL for webhook handlers with Igniter-powered code generation.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      maintainers: ["Eileen Noonan"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md": [title: "Changelog"]
      ],
      groups_for_modules: [
        "Core": [
          TinyElixirStripe,
          TinyElixirStripe.Client,
          TinyElixirStripe.WebhookHandler,
          TinyElixirStripe.WebhookController,
          TinyElixirStripe.WebhookSignature
        ],
        "Mix Tasks": [
          Mix.Tasks.TinyElixirStripe.Install,
          Mix.Tasks.TinyElixirStripe.Gen.Handler,
          Mix.Tasks.TinyElixirStripe.SetWebhookPath,
          Mix.Tasks.TinyElixirStripe.SyncWebhookHandlers,
          Mix.Tasks.TinyElixirStripe.UpdateSupportedEvents
        ],
        "Internal": [
          TinyElixirStripe.ParsersWithRawBody,
          TinyElixirStripe.WebhookHandler.Dsl,
          TinyElixirStripe.WebhookHandler.Info
        ]
      ]
    ]
  end
end
