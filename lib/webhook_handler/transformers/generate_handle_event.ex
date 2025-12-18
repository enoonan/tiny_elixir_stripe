defmodule TinyElixirStripe.WebhookHandler.Transformers.GenerateHandleEvent do
  @moduledoc """
  Transformer that generates handle_event/2 functions for webhook handlers.
  """

  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    handlers = TinyElixirStripe.WebhookHandler.Info.handlers(dsl_state)

    handle_event_code =
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

    {:ok, Spark.Dsl.Transformer.eval(dsl_state, [], handle_event_code)}
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
