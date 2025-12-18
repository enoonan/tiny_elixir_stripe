defmodule TinyElixirStripe.WebhookHandler.Dsl do
  @moduledoc """
  DSL extension for defining webhook handlers.
  """

  defmodule Handler do
    @moduledoc """
    Represents a webhook event handler.
    """
    defstruct [:event_type, :handler, :__spark_metadata__]
  end

  @handler %Spark.Dsl.Entity{
    name: :handle,
    args: [:event_type, :handler],
    target: Handler,
    describe: "Define a handler for a specific Stripe webhook event type",
    schema: [
      event_type: [
        type: :string,
        required: true,
        doc: "The Stripe event type to handle (e.g., 'customer.created')"
      ],
      handler: [
        type: {:or, [{:fun, 1}, :atom]},
        required: true,
        doc: "Either a 1-arity function or a module that implements handle_event/1"
      ]
    ]
  }

  @handlers %Spark.Dsl.Section{
    name: :handlers,
    top_level?: true,
    entities: [@handler],
    describe: "Define handlers for Stripe webhook events"
  }

  use Spark.Dsl.Extension,
    sections: [@handlers],
    transformers: [
      TinyElixirStripe.WebhookHandler.Transformers.GenerateHandleEvent
    ]
end
