defmodule PinStripe.WebhookController do
  @moduledoc """
  Base controller for handling Stripe webhook events.

  This module provides a `use` macro that injects webhook handling functionality
  into your Phoenix controller. It automatically verifies webhook signatures and
  dispatches events to handler functions defined using the `handle/2` macro.

  ## Usage

  Create a controller in your Phoenix app and define event handlers:

      defmodule MyAppWeb.StripeWebhookController do
        use PinStripe.WebhookController

        handle "customer.created", fn event ->
          # Process customer.created event
          customer = event["data"]["object"]
          IO.inspect(customer, label: "New customer")
          :ok
        end

        handle "invoice.paid", MyApp.InvoicePaidHandler
      end

  Then add it to your router:

      scope "/webhooks" do
        pipe_through [:api]

        post "/stripe", StripeWebhookController, :create
      end

  ## Configuration

  Configure your webhook secret:

      config :pin_stripe,
        stripe_webhook_secret: "whsec_..."

  ## Security

  This controller automatically verifies webhook signatures using the
  `stripe-signature` header. Invalid signatures are rejected with a 400 response.

  The raw request body must be available in `conn.assigns.raw_body` for signature
  verification to work. Use PinStripe.ParsersWithRawBody in your endpoint.

  ## Handler Functions

  Handlers can be either:
  - Anonymous functions that take the event as an argument
  - Module names that implement a `handle_event/1` function

  ### Function Handler Example

      handle "customer.created", fn event ->
        # Process customer.created event
        :ok
      end

  ### Module Handler Example

      handle "invoice.paid", MyApp.InvoicePaidHandler

  Then create the handler module:

      defmodule MyApp.InvoicePaidHandler do
        def handle_event(event) do
          invoice = event["data"]["object"]
          # Process the paid invoice
          :ok
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      use PinStripe.WebhookHandler
      use Phoenix.Controller, formats: [:json]
      import Plug.Conn
      require Logger
    end
  end
end
