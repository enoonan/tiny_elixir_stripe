defmodule TinyElixirStripe.WebhookHandlerTest do
  use ExUnit.Case, async: true

  defmodule TestHandler do
    use TinyElixirStripe.WebhookHandler

    handle "customer.created", fn event ->
      send(self(), {:customer_created, event})
      :ok
    end

    handle "customer.updated", TestHandler.CustomerUpdated

    handle "charge.succeeded", fn event ->
      send(self(), {:charge_succeeded, event})
      {:ok, :processed}
    end
  end

  defmodule TestHandler.CustomerUpdated do
    def handle_event(event) do
      send(self(), {:customer_updated, event})
      :ok
    end
  end

  describe "DSL definition" do
    test "defines handlers using handle/2 with function" do
      handlers = TinyElixirStripe.WebhookHandler.Info.handlers(TestHandler)

      assert length(handlers) == 3

      customer_created = Enum.find(handlers, &(&1.event_type == "customer.created"))
      assert customer_created
      assert is_function(customer_created.handler, 1)
    end

    test "defines handlers using handle/2 with module" do
      handlers = TinyElixirStripe.WebhookHandler.Info.handlers(TestHandler)

      customer_updated = Enum.find(handlers, &(&1.event_type == "customer.updated"))
      assert customer_updated
      assert customer_updated.handler == TestHandler.CustomerUpdated
    end
  end

  describe "handle_event/2" do
    test "dispatches to function handler" do
      event = %{"id" => "evt_123", "type" => "customer.created", "data" => %{}}

      assert :ok = TestHandler.handle_event("customer.created", event)
      assert_received {:customer_created, ^event}
    end

    test "dispatches to module handler" do
      event = %{"id" => "evt_456", "type" => "customer.updated", "data" => %{}}

      assert :ok = TestHandler.handle_event("customer.updated", event)
      assert_received {:customer_updated, ^event}
    end

    test "returns handler result" do
      event = %{"id" => "evt_789", "type" => "charge.succeeded", "data" => %{}}

      assert {:ok, :processed} = TestHandler.handle_event("charge.succeeded", event)
      assert_received {:charge_succeeded, ^event}
    end

    test "returns :ok for unknown event types" do
      event = %{"id" => "evt_999", "type" => "unknown.event", "data" => %{}}

      assert :ok = TestHandler.handle_event("unknown.event", event)
    end
  end

  describe "error handling" do
    defmodule ErrorHandler do
      use TinyElixirStripe.WebhookHandler

      handle "will.raise", fn _event ->
        raise "Something went wrong"
      end

      handle "will.error", fn _event ->
        {:error, :processing_failed}
      end
    end

    test "propagates errors from handlers" do
      event = %{"type" => "will.error"}

      assert {:error, :processing_failed} = ErrorHandler.handle_event("will.error", event)
    end

    test "propagates exceptions from handlers" do
      event = %{"type" => "will.raise"}

      assert_raise RuntimeError, "Something went wrong", fn ->
        ErrorHandler.handle_event("will.raise", event)
      end
    end
  end
end
