defmodule PinStripe.WebhookHandler.Transformers.GenerateHandleEvent do
  @moduledoc """
  Transformer that generates handle_event/2 functions and Phoenix controller code
  for webhook handlers.
  """

  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    handlers = PinStripe.WebhookHandler.Info.handlers(dsl_state)

    # Always generate controller code with handle_event/2 and Phoenix controller actions
    code = generate_controller_code(handlers)

    {:ok, Spark.Dsl.Transformer.eval(dsl_state, [], code)}
  end

  defp generate_controller_code(handlers) do
    quote do
      unquote(generate_handle_event_functions(handlers))
      unquote(generate_create_functions())
      unquote(generate_signature_functions())
    end
  end

  defp generate_handle_event_functions(handlers) do
    quote do
      @doc """
      Handles a webhook event by dispatching to the appropriate handler.

      Returns `:ok` or the result of the handler function.
      Unknown event types return `:ok`.
      """
      def handle_event(event_type, event)

      unquote(generate_handler_clauses(handlers))

      # Catch-all clause for unknown event types
      def handle_event(_event_type, _event), do: :ok
    end
  end

  defp generate_create_functions do
    quote do
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

          # Forward to this module's handle_event function
          __MODULE__.handle_event(type, params)

          send_resp(conn, 200, "")
        end
      end

      def create(conn, _params) do
        Logger.warning("[#{inspect(__MODULE__)}] Received webhook without type field")
        send_resp(conn, 400, "missing event type")
      end
    end
  end

  defp generate_signature_functions do
    quote do
      defp verify_signature(conn) do
        secret = Application.fetch_env!(:pin_stripe, :stripe_webhook_secret)
        "whsec_" <> _ = secret

        with {:ok, signature} <- get_signature(conn),
             raw_body <- reconstruct_raw_body(conn),
             :ok <- PinStripe.WebhookSignature.verify(raw_body, signature, secret) do
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

  defp generate_handler_clauses(handlers) do
    Enum.map(handlers, fn handler ->
      quote do
        def handle_event(unquote(handler.event_type), event) do
          unquote(call_handler(handler))
        end
      end
    end)
  end

  defp call_handler(handler) do
    case handler.handler do
      fun when is_function(fun, 1) ->
        quote do
          unquote(Macro.escape(fun)).(event)
        end

      module when is_atom(module) ->
        quote do
          unquote(module).handle_event(event)
        end
    end
  end
end
