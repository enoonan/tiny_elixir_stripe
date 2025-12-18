defmodule Mix.Tasks.TinyElixirStripe.SyncWebhookHandlersTest do
  use ExUnit.Case

  describe "Docs module" do
    test "has short_doc/0" do
      assert is_binary(Mix.Tasks.TinyElixirStripe.SyncWebhookHandlers.Docs.short_doc())
    end

    test "has example/0" do
      assert is_binary(Mix.Tasks.TinyElixirStripe.SyncWebhookHandlers.Docs.example())
    end

    test "has long_doc/0" do
      assert is_binary(Mix.Tasks.TinyElixirStripe.SyncWebhookHandlers.Docs.long_doc())
    end
  end

  if Code.ensure_loaded?(Igniter) do
    describe "info/2" do
      test "returns valid Task.Info struct" do
        info = Mix.Tasks.TinyElixirStripe.SyncWebhookHandlers.info([], nil)

        assert info.group == :tiny_elixir_stripe
        assert "tiny_elixir_stripe.gen.handler" in info.composes
        assert info.schema[:api_key] == :string
        assert info.schema[:handler_type] == :string
        assert info.schema[:skip_confirmation] == :boolean
        assert info.schema[:create_handler_module] == :string
      end
    end

    # Note: Full integration tests would require mocking the Stripe CLI
    # and file system operations. These tests verify the structure and
    # basic functionality of the task.
  end
end
