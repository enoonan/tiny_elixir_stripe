defmodule Mix.Tasks.TinyElixirStripe.InstallTest do
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
    |> Igniter.compose_task("tiny_elixir_stripe.install", [])
    |> then(fn igniter ->
      diff = Igniter.Test.diff(igniter, only: "lib/my_app/endpoint.ex")
      assert diff =~ "TinyElixirStripe.ParsersWithRawBody"
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
    |> Igniter.compose_task("tiny_elixir_stripe.install", [])
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
    |> Igniter.compose_task("tiny_elixir_stripe.install", ["--path", "/custom/webhook"])
    |> then(fn igniter ->
      diff = Igniter.Test.diff(igniter, only: "lib/my_app_web/router.ex")
      assert diff =~ "StripeWebhookController"
      assert diff =~ "/custom"
      igniter
    end)
  end

  test "warns when no endpoint is found" do
    test_project()
    |> Igniter.compose_task("tiny_elixir_stripe.install", [])
    |> assert_has_warning(
      "Could not find a Phoenix endpoint to modify. Please manually replace Plug.Parsers with TinyElixirStripe.ParsersWithRawBody."
    )
  end

  test "warns when no router is found" do
    test_project()
    |> Igniter.compose_task("tiny_elixir_stripe.install", [])
    |> assert_has_warning(
      "Could not find a Phoenix router to modify. Please manually add the webhook route."
    )
  end

  test "adds tiny_elixir_stripe to import_deps in .formatter.exs" do
    test_project()
    |> Igniter.compose_task("tiny_elixir_stripe.install", [])
    |> then(fn igniter ->
      diff = Igniter.Test.diff(igniter, only: ".formatter.exs")
      assert diff =~ "import_deps"
      assert diff =~ ":tiny_elixir_stripe"
      igniter
    end)
  end

  test "creates a webhook handler stub module in lib/{app}" do
    test_project()
    |> Igniter.compose_task("tiny_elixir_stripe.install", [])
    |> then(fn igniter ->
      # Check that the webhook handler module was created
      diff = Igniter.Test.diff(igniter, only: "lib/test/stripe_webhook_handlers.ex")
      assert diff =~ "use TinyElixirStripe.WebhookHandler"
      igniter
    end)
  end

  test "does not create a duplicate webhook handler if one already exists" do
    test_project()
    |> Igniter.Project.Module.create_module(Test.ExistingHandler, """
    use TinyElixirStripe.WebhookHandler

    handle "customer.created", fn event ->
      :ok
    end
    """)
    |> Igniter.compose_task("tiny_elixir_stripe.install", [])
    |> then(fn igniter ->
      # Check that no new webhook handler was created
      diff = Igniter.Test.diff(igniter, only: "lib/test/stripe_webhook_handlers.ex")
      assert diff == ""

      # Verify the existing handler is still there
      diff = Igniter.Test.diff(igniter, only: "lib/test/existing_handler.ex")
      assert diff =~ "use TinyElixirStripe.WebhookHandler"
      assert diff =~ "customer.created"
      igniter
    end)
  end

  test "creates a webhook controller in lib/{app}_web/controllers" do
    test_project()
    |> Igniter.compose_task("tiny_elixir_stripe.install", [])
    |> then(fn igniter ->
      # Check that the webhook controller was created in the controllers directory
      diff =
        Igniter.Test.diff(igniter, only: "lib/test_web/controllers/stripe_webhook_controller.ex")

      assert diff =~ "use TinyElixirStripe.WebhookController"
      assert diff =~ "handler: Test.StripeWebhookHandlers"
      igniter
    end)
  end

  test "routes to the generated webhook controller, not TinyElixirStripe.WebhookController" do
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
    |> Igniter.compose_task("tiny_elixir_stripe.install", [])
    |> then(fn igniter ->
      diff = Igniter.Test.diff(igniter, only: "lib/test_web/router.ex")
      assert diff =~ "StripeWebhookController"
      refute diff =~ "TinyElixirStripe.WebhookController"
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
    |> Igniter.compose_task("tiny_elixir_stripe.install", ["--path", "/custom/stripe"])
    |> then(fn igniter ->
      diff = Igniter.Test.diff(igniter, only: "lib/test_web/router.ex")
      assert diff =~ "StripeWebhookController"
      assert diff =~ "/custom"
      igniter
    end)
  end
end
