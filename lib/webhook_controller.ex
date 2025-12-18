defmodule TinyElixirStripe.WebhookController do
  @moduledoc """
  Base controller for handling Stripe webhook events.

  This module provides a `use` macro that injects webhook handling functionality
  into your Phoenix controller. It automatically verifies webhook signatures and
  forwards events to your handler module.

  ## Usage

  Create a controller in your Phoenix app:

      defmodule MyAppWeb.StripeWebhookController do
        use TinyElixirStripe.WebhookController, 
          handler: MyApp.StripeWebhookHandlers
      end

  Then add it to your router:

      scope "/webhooks" do
        pipe_through [:api]

        post "/stripe", StripeWebhookController, :create
      end

  ## Configuration

  Configure your webhook secret:

      config :tiny_elixir_stripe,
        stripe_webhook_secret: "whsec_..."

  ## Security

  This controller automatically verifies webhook signatures using the
  `stripe-signature` header. Invalid signatures are rejected with a 400 response.

  The raw request body must be available in `conn.assigns.raw_body` for signature
  verification to work. Use TinyElixirStripe.ParsersWithRawBody in your endpoint.

  ## Handler Module

  The handler module should use `TinyElixirStripe.WebhookHandler` and define
  event handlers:

      defmodule MyApp.StripeWebhookHandlers do
        use TinyElixirStripe.WebhookHandler

        handle "customer.created", fn event ->
          # Process customer.created event
          :ok
        end

        handle "invoice.paid", fn event ->
          # Process invoice.paid event
          :ok
        end
      end
  """

  defmacro __using__(opts) do
    handler = Keyword.fetch!(opts, :handler)

    quote location: :keep do
      use Phoenix.Controller, formats: [:json]
      import Plug.Conn
      require Logger

      @handler unquote(handler)

      @doc """
      Handles incoming Stripe webhook events.

      Expects a JSON payload with at least a "type" field indicating the event type.
      """
      def create(conn, %{"type" => type} = params) do
        conn = verify_signature(conn)

        if conn.halted do
          conn
        else
          Logger.info("[#{inspect(__MODULE__)}] Received webhook: #{type}")

          # Forward to handler module
          @handler.handle_event(type, params)

          send_resp(conn, 200, "")
        end
      end

      def create(conn, _params) do
        Logger.warning("[#{inspect(__MODULE__)}] Received webhook without type field")
        send_resp(conn, 400, "missing event type")
      end

      defp verify_signature(conn) do
        secret = Application.fetch_env!(:tiny_elixir_stripe, :stripe_webhook_secret)
        "whsec_" <> _ = secret

        with {:ok, signature} <- get_signature(conn),
             raw_body <- reconstruct_raw_body(conn),
             :ok <- TinyElixirStripe.WebhookSignature.verify(raw_body, signature, secret) do
          conn
        else
          {:error, error} ->
            Logger.error("[#{inspect(__MODULE__)}] Invalid signature: #{error}")

            conn
            |> send_resp(400, "invalid signature")
            |> halt()
        end
      end

      defp get_signature(conn) do
        case get_req_header(conn, "stripe-signature") do
          [signature] -> {:ok, signature}
          _ -> {:error, "no signature"}
        end
      end

      defp reconstruct_raw_body(conn) do
        # Chunks are prepended, so reverse before concatenating
        conn.assigns.raw_body
        |> Enum.reverse()
        |> IO.iodata_to_binary()
      end
    end
  end
end
