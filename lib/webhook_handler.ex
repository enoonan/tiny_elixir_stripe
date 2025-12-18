defmodule TinyElixirStripe.WebhookHandler do
  @moduledoc """
  Spark DSL for defining webhook handlers.

  This module provides a DSL for defining handlers for Stripe webhook events.

  ## Example

      defmodule MyApp.StripeWebhookHandlers do
        use TinyElixirStripe.WebhookHandler

        handle "customer.created", fn event ->
          # Process customer.created event
          :ok
        end

        handle "charge.succeeded", MyApp.ChargeHandler
      end

  Handlers can be either:
  - Anonymous functions that take the event as an argument
  - Module names that implement a `handle_event/1` function
  """

  use Spark.Dsl,
    default_extensions: [
      extensions: [TinyElixirStripe.WebhookHandler.Dsl]
    ]
end
