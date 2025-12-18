defmodule Mix.Tasks.TinyElixirStripe.SetWebhookPathTest do
  use ExUnit.Case, async: true
  import Igniter.Test

  test "adds new webhook route" do
    test_project()
    |> Igniter.Project.Module.create_module(MyAppWeb.Router, """
    use MyAppWeb, :router

    pipeline :api do
      plug :accepts, ["json"]
    end
    """)
    |> Igniter.compose_task("tiny_elixir_stripe.set_webhook_path", ["/api/stripe-webhook"])
    |> then(fn igniter ->
      diff = Igniter.Test.diff(igniter, only: "lib/my_app_web/router.ex")
      # New route should be added
      assert diff =~ "StripeWebhookController"
      assert diff =~ "/api" or diff =~ "stripe-webhook"
      igniter
    end)
  end

  test "adds webhook route with multi-part path" do
    test_project()
    |> Igniter.Project.Module.create_module(MyAppWeb.Router, """
    use MyAppWeb, :router

    pipeline :api do
      plug :accepts, ["json"]
    end
    """)
    |> Igniter.compose_task("tiny_elixir_stripe.set_webhook_path", ["/webhooks/stripe"])
    |> then(fn igniter ->
      diff = Igniter.Test.diff(igniter, only: "lib/my_app_web/router.ex")
      # New route should be added
      assert diff =~ "StripeWebhookController"
      assert diff =~ "/webhooks"
      igniter
    end)
  end

  test "adds webhook route with single path segment" do
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
    |> Igniter.compose_task("tiny_elixir_stripe.set_webhook_path", ["/stripe-webhook"])
    |> then(fn igniter ->
      diff = Igniter.Test.diff(igniter, only: "lib/my_app_web/router.ex")
      # New route should be added in /api scope
      assert diff =~ "StripeWebhookController"
      assert diff =~ "stripe-webhook"
      igniter
    end)
  end

  test "warns when no router is found" do
    test_project()
    |> Igniter.compose_task("tiny_elixir_stripe.set_webhook_path", ["/new/path"])
    |> assert_has_warning(
      "Could not find a Phoenix router. Please manually add the webhook route."
    )
  end

  test "raises error when no path is provided" do
    assert_raise ArgumentError, ~r/Required positional argument.*path/, fn ->
      test_project()
      |> Igniter.compose_task("tiny_elixir_stripe.set_webhook_path", [])
      |> apply_igniter!()
    end
  end
end
