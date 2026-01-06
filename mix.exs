defmodule PinStripe.MixProject do
  use Mix.Project

  @version "0.3.2"
  @source_url "https://github.com/enoonan/pin_stripe"

  def project do
    [
      app: :pin_stripe,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Hex
      description: description(),
      package: package(),

      # Docs
      name: "PinStripe",
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
      {:usage_rules, "~> 0.1", only: [:dev, :test], runtime: false},
      {:req, "~> 0.5.0"},
      {:spark, "~> 2.3"},
      {:igniter, "~> 0.6", optional: true},
      {:phoenix, "~> 1.7", optional: true}
    ]
  end

  defp description do
    """
    A minimalist Stripe SDK for Elixir.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      maintainers: ["Eileen Noonan"],
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE CHANGELOG.md usage-rules.md)
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
        Core: [
          PinStripe,
          PinStripe.Client,
          PinStripe.WebhookHandler,
          PinStripe.WebhookController,
          PinStripe.WebhookSignature
        ],
        Testing: [
          PinStripe.Test.Mock,
          PinStripe.Test.Fixtures
        ],
        "Mix Tasks": [
          Mix.Tasks.PinStripe.Install,
          Mix.Tasks.PinStripe.Gen.Handler,
          Mix.Tasks.PinStripe.SetWebhookPath,
          Mix.Tasks.PinStripe.SyncApiVersion,
          Mix.Tasks.PinStripe.SyncWebhookHandlers,
          Mix.Tasks.PinStripe.UpdateSupportedEvents
        ],
        Internal: [
          PinStripe.ParsersWithRawBody,
          PinStripe.WebhookHandler.Dsl,
          PinStripe.WebhookHandler.Info
        ]
      ]
    ]
  end
end
