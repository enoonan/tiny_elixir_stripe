defmodule TinyElixirStripe.WebhookHandler.Info do
  @moduledoc """
  Introspection functions for webhook handler DSL.
  """

  use Spark.InfoGenerator,
    extension: TinyElixirStripe.WebhookHandler.Dsl,
    sections: [:handlers]
end
