defmodule Mix.Tasks.PinStripe.InstallTest do
  use ExUnit.Case, async: true
  import Igniter.Test

  test "replaces Plug.Parsers with ParsersWithRawBody in endpoint" do
    test_project()
    |> Igniter.Project.Module.create_module(MyApp.Endpoint, """
    use Phoenix.Endpoint, otp_app: :my_app

    plug Plug.Parsers,
      parsers: [:urlencoded, :multipart, :json],
      pass: ["*/*"],
      json_decoder: Phoenix.json_library()
    """)
    |> Igniter.compose_task("pin_stripe.install", [])
    |> then(fn igniter ->
      diff = Igniter.Test.diff(igniter, only: "lib/my_app/endpoint.ex")
      assert diff =~ "PinStripe.ParsersWithRawBody"
      igniter
    end)
  end

  test "adds webhook route to router with default path" do
    test_project()
    |> Igniter.Project.Module.create_module(MyAppWeb.Router, """
    use MyAppWeb, :router

    pipeline :api do
      plug :accepts, ["json"]
    end

    scope "/api", MyAppWeb do
      pipe_through :api
    end
    """)
    |> Igniter.compose_task("pin_stripe.install", [])
    |> then(fn igniter ->
      # Check that the file was modified
      diff = Igniter.Test.diff(igniter, only: "lib/my_app_web/router.ex")
      assert diff =~ "StripeWebhookController"
      assert diff =~ "/webhooks"
      assert diff =~ "/stripe"
      igniter
    end)
  end

  test "adds webhook route with custom path" do
    test_project()
    |> Igniter.Project.Module.create_module(MyAppWeb.Router, """
    use MyAppWeb, :router

    pipeline :api do
      plug :accepts, ["json"]
    end

    scope "/api", MyAppWeb do
      pipe_through :api
    end
    """)
    |> Igniter.compose_task("pin_stripe.install", ["--path", "/custom/webhook"])
    |> then(fn igniter ->
      diff = Igniter.Test.diff(igniter, only: "lib/my_app_web/router.ex")
      assert diff =~ "StripeWebhookController"
      assert diff =~ "/custom"
      igniter
    end)
  end

  test "warns when no endpoint is found" do
    test_project()
    |> Igniter.compose_task("pin_stripe.install", [])
    |> assert_has_warning(
      "Could not find a Phoenix endpoint to modify. Please manually replace Plug.Parsers with PinStripe.ParsersWithRawBody."
    )
  end

  test "warns when no router is found" do
    test_project()
    |> Igniter.compose_task("pin_stripe.install", [])
    |> assert_has_warning(
      "Could not find a Phoenix router to modify. Please manually add the webhook route."
    )
  end

  test "adds pin_stripe to import_deps in .formatter.exs" do
    test_project()
    |> Igniter.compose_task("pin_stripe.install", [])
    |> then(fn igniter ->
      diff = Igniter.Test.diff(igniter, only: ".formatter.exs")
      assert diff =~ "import_deps"
      assert diff =~ ":pin_stripe"
      igniter
    end)
  end

  test "creates a webhook controller in lib/{app}_web with example handlers" do
    test_project()
    |> Igniter.compose_task("pin_stripe.install", [])
    |> then(fn igniter ->
      # Check that the webhook controller was created
      diff = Igniter.Test.diff(igniter, only: "lib/test_web/stripe_webhook_controller.ex")

      assert diff =~ "use PinStripe.WebhookController"
      assert diff =~ "# Add your webhook event handlers here using the handle/2 macro"
      assert diff =~ "# handle \"customer.created\", fn event ->"
      assert diff =~ "# handle \"invoice.paid\", MyApp.InvoicePaidHandler"

      igniter
    end)
  end

  test "routes to the generated webhook controller, not PinStripe.WebhookController" do
    test_project()
    |> Igniter.Project.Module.create_module(TestWeb.Router, """
    use TestWeb, :router

    pipeline :api do
      plug :accepts, ["json"]
    end

    scope "/api", TestWeb do
      pipe_through :api
    end
    """)
    |> Igniter.compose_task("pin_stripe.install", [])
    |> then(fn igniter ->
      diff = Igniter.Test.diff(igniter, only: "lib/test_web/router.ex")
      assert diff =~ "StripeWebhookController"
      refute diff =~ "PinStripe.WebhookController"
      igniter
    end)
  end

  test "uses custom webhook path in generated controller route" do
    test_project()
    |> Igniter.Project.Module.create_module(TestWeb.Router, """
    use TestWeb, :router

    pipeline :api do
      plug :accepts, ["json"]
    end

    scope "/api", TestWeb do
      pipe_through :api
    end
    """)
    |> Igniter.compose_task("pin_stripe.install", ["--path", "/custom/stripe"])
    |> then(fn igniter ->
      diff = Igniter.Test.diff(igniter, only: "lib/test_web/router.ex")
      assert diff =~ "StripeWebhookController"
      assert diff =~ "/custom"
      igniter
    end)
  end
end
