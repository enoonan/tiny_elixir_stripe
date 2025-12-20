defmodule PinStripe.WebhookControllerTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn
  import ExUnit.CaptureLog

  alias PinStripe.WebhookSignature

  @webhook_secret "whsec_test_secret_key_12345"

  # Test controller using the macro with inline handlers
  defmodule TestWebhookController do
    use PinStripe.WebhookController

    handle "customer.created", fn event ->
      send(self(), {:handled, "customer.created", event})
      :ok
    end

    handle "invoice.paid", fn event ->
      send(self(), {:handled, "invoice.paid", event})
      {:ok, :processed}
    end
  end

  setup do
    # Set up valid config
    Application.put_env(:pin_stripe, :stripe_webhook_secret, @webhook_secret)

    on_exit(fn ->
      Application.delete_env(:pin_stripe, :stripe_webhook_secret)
    end)

    :ok
  end

  describe "__using__ macro" do
    test "injects a create/2 function" do
      assert function_exported?(TestWebhookController, :create, 2)
    end
  end

  describe "create/2 with valid signature" do
    test "accepts valid webhook with correct signature" do
      payload = %{"type" => "customer.created", "id" => "evt_123"}
      conn = build_webhook_conn(payload)

      conn = TestWebhookController.create(conn, payload)

      assert conn.status == 200
      assert conn.resp_body == ""
      refute conn.halted
    end

    test "forwards event to handler module" do
      payload = %{"type" => "customer.created", "id" => "evt_123", "data" => %{"object" => %{}}}
      conn = build_webhook_conn(payload)

      TestWebhookController.create(conn, payload)

      assert_received {:handled, "customer.created", ^payload}
    end

    test "accepts different event types and forwards to handler" do
      payload = %{"type" => "invoice.paid", "id" => "evt_test"}
      conn = build_webhook_conn(payload)

      conn = TestWebhookController.create(conn, payload)

      assert conn.status == 200
      assert_received {:handled, "invoice.paid", ^payload}
    end

    test "handles unregistered event types gracefully" do
      payload = %{"type" => "payment_intent.succeeded", "id" => "evt_test"}
      conn = build_webhook_conn(payload)

      conn = TestWebhookController.create(conn, payload)

      assert conn.status == 200
      refute_received {:handled, _, _}
    end

    test "logs webhook event type" do
      # Temporarily enable info logging for this test
      original_level = Logger.level()
      Logger.configure(level: :info)

      payload = %{"type" => "customer.created", "id" => "evt_123"}
      conn = build_webhook_conn(payload)

      log =
        capture_log(fn ->
          TestWebhookController.create(conn, payload)
        end)

      assert log =~ "Received webhook: customer.created"

      # Restore original log level
      Logger.configure(level: original_level)
    end

    test "accepts webhook with empty data" do
      payload = %{"type" => "test.event", "id" => "evt_test", "data" => %{}}
      conn = build_webhook_conn(payload)

      conn = TestWebhookController.create(conn, payload)

      assert conn.status == 200
    end
  end

  describe "create/2 without type field" do
    test "rejects webhook without type field" do
      payload = %{"id" => "evt_123", "data" => %{}}
      conn = build_webhook_conn(payload)

      log =
        capture_log(fn ->
          conn = TestWebhookController.create(conn, payload)
          assert conn.status == 400
          assert conn.resp_body == "missing event type"
        end)

      assert log =~ "Received webhook without type field"
    end
  end

  describe "verify_signature plug" do
    test "accepts valid signature" do
      payload = %{"type" => "customer.created", "id" => "evt_123"}
      conn = build_webhook_conn(payload)

      conn = TestWebhookController.create(conn, payload)

      assert conn.status == 200
      refute conn.halted
    end

    test "rejects webhook with invalid signature" do
      payload = %{"type" => "customer.created", "id" => "evt_123"}
      payload_json = Jason.encode!(payload)

      # Create invalid signature
      invalid_signature = "t=#{System.system_time(:second)},v1=invalid_hash_1234567890abcdef"

      conn =
        conn(:post, "/webhooks/stripe", payload_json)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", invalid_signature)
        |> assign(:raw_body, [payload_json])

      log =
        capture_log(fn ->
          conn = TestWebhookController.create(conn, payload)
          assert conn.status == 400
          assert conn.resp_body == "invalid signature"
          assert conn.halted
        end)

      assert log =~ "Invalid signature"
    end

    test "rejects webhook with expired signature" do
      payload = %{"type" => "customer.created", "id" => "evt_123"}
      # Create signature that's 301 seconds old (expired)
      timestamp = System.system_time(:second) - 301
      conn = build_webhook_conn(payload, timestamp)

      log =
        capture_log(fn ->
          conn = TestWebhookController.create(conn, payload)
          assert conn.status == 400
          assert conn.resp_body == "invalid signature"
          assert conn.halted
        end)

      assert log =~ "Invalid signature"
      assert log =~ "signature is expired"
    end

    test "rejects webhook without signature header" do
      payload = %{"type" => "customer.created", "id" => "evt_123"}
      payload_json = Jason.encode!(payload)

      conn =
        conn(:post, "/webhooks/stripe", payload_json)
        |> put_req_header("content-type", "application/json")
        |> assign(:raw_body, [payload_json])

      log =
        capture_log(fn ->
          conn = TestWebhookController.create(conn, payload)
          assert conn.status == 400
          assert conn.resp_body == "invalid signature"
          assert conn.halted
        end)

      assert log =~ "Invalid signature"
      assert log =~ "no signature"
    end

    test "rejects webhook with malformed signature header" do
      payload = %{"type" => "customer.created", "id" => "evt_123"}
      payload_json = Jason.encode!(payload)

      conn =
        conn(:post, "/webhooks/stripe", payload_json)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", "invalid_format")
        |> assign(:raw_body, [payload_json])

      log =
        capture_log(fn ->
          conn = TestWebhookController.create(conn, payload)
          assert conn.status == 400
          assert conn.resp_body == "invalid signature"
          assert conn.halted
        end)

      assert log =~ "Invalid signature"
    end

    test "rejects webhook with modified payload" do
      original_payload = %{"type" => "customer.created", "id" => "evt_123"}
      original_json = Jason.encode!(original_payload)

      # Create signature for original payload
      timestamp = System.system_time(:second)
      signature = WebhookSignature.sign(original_json, timestamp, @webhook_secret)

      # Attacker modifies the raw body but keeps the original signature
      modified_payload = %{"type" => "customer.deleted", "id" => "evt_123"}
      modified_json = Jason.encode!(modified_payload)

      conn =
        conn(:post, "/webhooks/stripe", modified_json)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", signature)
        |> assign(:raw_body, [modified_json])

      log =
        capture_log(fn ->
          conn = TestWebhookController.create(conn, modified_payload)
          assert conn.status == 400
          assert conn.resp_body == "invalid signature"
          assert conn.halted
        end)

      assert log =~ "Invalid signature"
      assert log =~ "signature is incorrect"
    end

    test "requires secret to start with whsec_ prefix" do
      Application.put_env(:pin_stripe, :stripe_webhook_secret, "invalid_secret")

      payload = %{"type" => "customer.created", "id" => "evt_123"}
      conn = build_webhook_conn(payload)

      assert_raise MatchError, fn ->
        TestWebhookController.create(conn, payload)
      end
    end
  end

  describe "DSL definition" do
    test "defines handlers using handle/2 with function" do
      handlers = PinStripe.WebhookHandler.Info.handlers(TestWebhookController)

      assert length(handlers) == 2

      customer_created = Enum.find(handlers, &(&1.event_type == "customer.created"))
      assert customer_created
      assert is_function(customer_created.handler, 1)
    end

    test "defines handlers using handle/2 with module" do
      # Create a test controller with a module handler
      defmodule TestModuleHandler do
        def handle_event(event) do
          send(self(), {:module_handled, event})
          :ok
        end
      end

      defmodule TestControllerWithModuleHandler do
        use PinStripe.WebhookController

        handle "customer.updated", TestModuleHandler
      end

      handlers = PinStripe.WebhookHandler.Info.handlers(TestControllerWithModuleHandler)

      customer_updated = Enum.find(handlers, &(&1.event_type == "customer.updated"))
      assert customer_updated
      assert customer_updated.handler == TestModuleHandler
    end
  end

  describe "handle_event/2 dispatching" do
    test "dispatches to function handler" do
      event = %{"id" => "evt_123", "type" => "customer.created", "data" => %{}}

      assert :ok = TestWebhookController.handle_event("customer.created", event)
      assert_received {:handled, "customer.created", ^event}
    end

    test "dispatches to module handler" do
      defmodule ModuleHandlerForDispatch do
        def handle_event(event) do
          send(self(), {:module_dispatched, event})
          :ok
        end
      end

      defmodule TestControllerForDispatch do
        use PinStripe.WebhookController

        handle "test.event", ModuleHandlerForDispatch
      end

      event = %{"id" => "evt_456", "type" => "test.event", "data" => %{}}

      assert :ok = TestControllerForDispatch.handle_event("test.event", event)
      assert_received {:module_dispatched, ^event}
    end

    test "returns handler result" do
      event = %{"id" => "evt_789", "type" => "invoice.paid", "data" => %{}}

      assert {:ok, :processed} = TestWebhookController.handle_event("invoice.paid", event)
      assert_received {:handled, "invoice.paid", ^event}
    end

    test "returns :ok for unknown event types" do
      event = %{"id" => "evt_999", "type" => "unknown.event", "data" => %{}}

      assert :ok = TestWebhookController.handle_event("unknown.event", event)
    end
  end

  describe "handler error handling" do
    defmodule ErrorHandlerController do
      use PinStripe.WebhookController

      handle "will.raise", fn _event ->
        raise "Something went wrong"
      end

      handle "will.error", fn _event ->
        {:error, :processing_failed}
      end
    end

    test "propagates errors from handlers" do
      event = %{"type" => "will.error"}

      assert {:error, :processing_failed} =
               ErrorHandlerController.handle_event("will.error", event)
    end

    test "propagates exceptions from handlers" do
      event = %{"type" => "will.raise"}

      assert_raise RuntimeError, "Something went wrong", fn ->
        ErrorHandlerController.handle_event("will.raise", event)
      end
    end
  end

  describe "raw_body handling" do
    test "correctly reconstructs raw body from chunks" do
      payload = %{"type" => "customer.created", "id" => "evt_123"}
      payload_json = Jason.encode!(payload)

      # Simulate multiple chunks (prepended in reverse order)
      chunk1 = String.slice(payload_json, 0, 20)
      chunk2 = String.slice(payload_json, 20, 100)

      timestamp = System.system_time(:second)
      signature = WebhookSignature.sign(payload_json, timestamp, @webhook_secret)

      conn =
        conn(:post, "/webhooks/stripe", payload_json)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", signature)
        |> assign(:raw_body, [chunk2, chunk1])

      conn = TestWebhookController.create(conn, payload)

      assert conn.status == 200
    end

    test "handles empty raw_body chunks" do
      payload = %{"type" => "customer.created", "id" => "evt_123"}
      payload_json = Jason.encode!(payload)

      timestamp = System.system_time(:second)
      signature = WebhookSignature.sign(payload_json, timestamp, @webhook_secret)

      conn =
        conn(:post, "/webhooks/stripe", payload_json)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", signature)
        |> assign(:raw_body, ["", payload_json, ""])

      conn = TestWebhookController.create(conn, payload)

      assert conn.status == 200
    end
  end

  # Helper functions

  defp build_webhook_conn(payload, timestamp \\ nil) do
    timestamp = timestamp || System.system_time(:second)
    payload_json = Jason.encode!(payload)

    signature = WebhookSignature.sign(payload_json, timestamp, @webhook_secret)

    conn(:post, "/webhooks/stripe", payload_json)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("stripe-signature", signature)
    |> assign(:raw_body, [payload_json])
  end
end
