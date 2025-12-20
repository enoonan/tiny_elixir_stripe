defmodule Mix.Tasks.PinStripe.Gen.HandlerTest do
  use ExUnit.Case, async: true
  import Igniter.Test

  describe "validation" do
    test "raises error when no event name is provided" do
      assert_raise ArgumentError, ~r/Required positional argument `event`/, fn ->
        test_project()
        |> Igniter.compose_task("pin_stripe.gen.handler", [])
      end
    end

    test "raises error when invalid event name is provided" do
      assert_raise ArgumentError, ~r/not a valid Stripe event/, fn ->
        test_project()
        |> Igniter.compose_task("pin_stripe.gen.handler", ["invalid.event.name"])
      end
    end

    test "accepts valid Stripe event names" do
      # Should not raise
      test_project()
      |> Igniter.Project.Module.create_module(MyAppWeb.StripeWebhookController, """
      use PinStripe.WebhookController
      """)
      |> Igniter.compose_task("pin_stripe.gen.handler", [
        "customer.created",
        "--handler-type",
        "function"
      ])
    end
  end

  describe "webhook handler module" do
    test "finds existing webhook handler module" do
      test_project()
      |> Igniter.Project.Module.create_module(MyAppWeb.StripeWebhookController, """
      use PinStripe.WebhookController
      """)
      |> Igniter.compose_task("pin_stripe.gen.handler", [
        "customer.created",
        "--handler-type",
        "function"
      ])
      |> then(fn igniter ->
        # Should modify the existing module, not create a new one
        diff = Igniter.Test.diff(igniter, only: "lib/my_app_web/stripe_webhook_controller.ex")
        assert diff =~ ~s("customer.created")
        assert diff =~ ~s(fn event ->)
        igniter
      end)
    end

    test "creates webhook handler module if it doesn't exist when specified via option" do
      # This test verifies the same behavior as the --create-handler-module option
      # by directly creating the module and then adding a handler
      test_project()
      |> Igniter.Project.Module.create_module(MyAppWeb.StripeWebhookController, """
      use PinStripe.WebhookController
      """)
      |> Igniter.compose_task("pin_stripe.gen.handler", [
        "customer.created",
        "--handler-type",
        "function"
      ])
      |> then(fn igniter ->
        # Should have the module with the handler
        diff = Igniter.Test.diff(igniter, only: "lib/my_app_web/stripe_webhook_controller.ex")
        assert diff =~ "use PinStripe.WebhookController"
        assert diff =~ ~s("customer.created")
        assert diff =~ ~s(fn event ->)
        igniter
      end)
    end
  end

  describe "function handler generation" do
    test "generates function handler stub" do
      test_project()
      |> Igniter.Project.Module.create_module(MyAppWeb.StripeWebhookController, """
      use PinStripe.WebhookController
      """)
      |> Igniter.compose_task("pin_stripe.gen.handler", [
        "customer.created",
        "--handler-type",
        "function"
      ])
      |> then(fn igniter ->
        diff = Igniter.Test.diff(igniter, only: "lib/my_app_web/stripe_webhook_controller.ex")
        assert diff =~ ~s("customer.created")
        assert diff =~ ~s(fn event ->)
        assert diff =~ "# Handle customer.created event"
        assert diff =~ ":ok"
        igniter
      end)
    end

    test "generates function handler for event with multiple dots" do
      test_project()
      |> Igniter.Project.Module.create_module(MyAppWeb.StripeWebhookController, """
      use PinStripe.WebhookController
      """)
      |> Igniter.compose_task("pin_stripe.gen.handler", [
        "checkout.session.completed",
        "--handler-type",
        "function"
      ])
      |> then(fn igniter ->
        diff = Igniter.Test.diff(igniter, only: "lib/my_app_web/stripe_webhook_controller.ex")
        assert diff =~ ~s("checkout.session.completed")
        assert diff =~ ~s(fn event ->)
        assert diff =~ "# Handle checkout.session.completed event"
        igniter
      end)
    end
  end

  describe "module handler generation" do
    test "generates module handler stub with default location" do
      test_project()
      |> Igniter.Project.Module.create_module(MyAppWeb.StripeWebhookController, """
      use PinStripe.WebhookController
      """)
      |> Igniter.compose_task("pin_stripe.gen.handler", [
        "customer.created",
        "--handler-type",
        "module"
      ])
      |> then(fn igniter ->
        # Should add handle call to webhook handler module
        handler_diff =
          Igniter.Test.diff(igniter, only: "lib/my_app_web/stripe_webhook_controller.ex")

        assert handler_diff =~ ~s("customer.created")
        assert handler_diff =~ "Test.StripeWebhookHandlers.CustomerCreated"

        # Should create the handler module
        module_diff =
          Igniter.Test.diff(igniter,
            only: "lib/test/stripe_webhook_handlers/customer_created.ex"
          )

        assert module_diff =~ "defmodule Test.StripeWebhookHandlers.CustomerCreated"
        assert module_diff =~ "def handle_event(event)"
        assert module_diff =~ "# Handle customer.created event"
        assert module_diff =~ ":ok"
        igniter
      end)
    end

    test "generates module handler with correct naming for multi-part events" do
      test_project()
      |> Igniter.Project.Module.create_module(MyAppWeb.StripeWebhookController, """
      use PinStripe.WebhookController
      """)
      |> Igniter.compose_task("pin_stripe.gen.handler", [
        "checkout.session.completed",
        "--handler-type",
        "module"
      ])
      |> then(fn igniter ->
        # Should add handle call
        handler_diff =
          Igniter.Test.diff(igniter, only: "lib/my_app_web/stripe_webhook_controller.ex")

        assert handler_diff =~ ~s("checkout.session.completed")
        assert handler_diff =~ "Test.StripeWebhookHandlers.CheckoutSessionCompleted"

        # Should create module with correct name
        module_diff =
          Igniter.Test.diff(igniter,
            only: "lib/test/stripe_webhook_handlers/checkout_session_completed.ex"
          )

        assert module_diff =~ "defmodule Test.StripeWebhookHandlers.CheckoutSessionCompleted"
        assert module_diff =~ "# Handle checkout.session.completed event"
        igniter
      end)
    end

    test "generates module handler with custom module name" do
      test_project()
      |> Igniter.Project.Module.create_module(MyAppWeb.StripeWebhookController, """
      use PinStripe.WebhookController
      """)
      |> Igniter.compose_task("pin_stripe.gen.handler", [
        "customer.created",
        "--handler-type",
        "module",
        "--module",
        "MyApp.CustomHandlers.NewCustomer"
      ])
      |> then(fn igniter ->
        # Should add handle call with custom module
        handler_diff =
          Igniter.Test.diff(igniter, only: "lib/my_app_web/stripe_webhook_controller.ex")

        assert handler_diff =~ ~s("customer.created")
        assert handler_diff =~ "MyApp.CustomHandlers.NewCustomer"

        # Should create module at custom location
        module_diff =
          Igniter.Test.diff(igniter, only: "lib/my_app/custom_handlers/new_customer.ex")

        assert module_diff =~ "defmodule MyApp.CustomHandlers.NewCustomer"
        igniter
      end)
    end
  end

  describe "handle call placement" do
    test "adds handle call to existing webhook handler module" do
      test_project()
      |> Igniter.Project.Module.create_module(MyAppWeb.StripeWebhookController, """
      use PinStripe.WebhookController

      handle "charge.succeeded", fn event ->
        # Existing handler
        :ok
      end
      """)
      |> Igniter.compose_task("pin_stripe.gen.handler", [
        "customer.created",
        "--handler-type",
        "function"
      ])
      |> then(fn igniter ->
        diff = Igniter.Test.diff(igniter, only: "lib/my_app_web/stripe_webhook_controller.ex")
        # Should have both handlers
        assert diff =~ ~s("charge.succeeded")
        assert diff =~ ~s("customer.created")
        igniter
      end)
    end

    test "does not duplicate handler for same event" do
      test_project()
      |> Igniter.Project.Module.create_module(MyAppWeb.StripeWebhookController, """
      use PinStripe.WebhookController

      handle "customer.created", fn event ->
        # Existing handler
        :ok
      end
      """)
      |> Igniter.compose_task("pin_stripe.gen.handler", [
        "customer.created",
        "--handler-type",
        "function"
      ])
      |> assert_has_warning(fn warning -> warning =~ ~r/already exists in/ end)
    end

    test "does not confuse documentation examples for actual handlers" do
      test_project()
      |> Igniter.Project.Module.create_module(MyAppWeb.StripeWebhookController, """
      use PinStripe.WebhookController

      @moduledoc \"\"\"
      Example usage:

          handle "customer.created", fn event ->
            # Handle the event
            :ok
          end
      \"\"\"
      """)
      |> Igniter.compose_task("pin_stripe.gen.handler", [
        "customer.created",
        "--handler-type",
        "function"
      ])
      |> then(fn igniter ->
        # Should successfully add the handler, not warn about duplication
        diff = Igniter.Test.diff(igniter, only: "lib/my_app_web/stripe_webhook_controller.ex")
        assert diff =~ ~s("customer.created")
        assert diff =~ ~s(fn event ->)

        # Should not have any warnings
        refute Enum.any?(igniter.issues, fn issue -> issue.severity == :warning end)
        igniter
      end)
    end
  end

  describe "edge cases" do
    test "handles events with underscores" do
      test_project()
      |> Igniter.Project.Module.create_module(MyAppWeb.StripeWebhookController, """
      use PinStripe.WebhookController
      """)
      |> Igniter.compose_task("pin_stripe.gen.handler", [
        "customer_cash_balance_transaction.created",
        "--handler-type",
        "module"
      ])
      |> then(fn igniter ->
        handler_diff =
          Igniter.Test.diff(igniter, only: "lib/my_app_web/stripe_webhook_controller.ex")

        assert handler_diff =~ ~s("customer_cash_balance_transaction.created")
        assert handler_diff =~ "Test.StripeWebhookHandlers.CustomerCashBalanceTransactionCreated"

        module_diff =
          Igniter.Test.diff(igniter,
            only:
              "lib/test/stripe_webhook_handlers/customer_cash_balance_transaction_created.ex"
          )

        assert module_diff =~
                 "defmodule Test.StripeWebhookHandlers.CustomerCashBalanceTransactionCreated"

        igniter
      end)
    end

    test "handles v1 prefixed events" do
      test_project()
      |> Igniter.Project.Module.create_module(MyAppWeb.StripeWebhookController, """
      use PinStripe.WebhookController
      """)
      |> Igniter.compose_task("pin_stripe.gen.handler", [
        "v1.billing.meter.error_report_triggered",
        "--handler-type",
        "module"
      ])
      |> then(fn igniter ->
        module_diff =
          Igniter.Test.diff(igniter,
            only: "lib/test/stripe_webhook_handlers/v1_billing_meter_error_report_triggered.ex"
          )

        assert module_diff =~
                 "defmodule Test.StripeWebhookHandlers.V1BillingMeterErrorReportTriggered"

        igniter
      end)
    end
  end
end
