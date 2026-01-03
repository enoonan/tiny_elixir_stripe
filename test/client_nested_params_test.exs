defmodule PinStripe.ClientNestedParamsTest do
  @moduledoc """
  Tests for nested parameter encoding in the Stripe API client.

  This test demonstrates a bug where nested maps (like metadata and recurring)
  cause Protocol.UndefinedError because Req's :form option cannot encode nested maps.

  Related issue: https://github.com/beam-community/stripity_stripe/issues/210
  """
  use ExUnit.Case, async: true

  alias PinStripe.Client

  describe "create with nested parameters" do
    test "creates customer with metadata" do
      # Set up a stub that expects properly encoded form data
      Req.Test.stub(PinStripe, fn conn ->
        # Verify the request body contains properly encoded metadata
        assert conn.body_params["metadata[user_id]"] == "123" or
                 conn.body_params["metadata"]["user_id"] == "123"

        Req.Test.json(conn, %{
          "id" => "cus_test123",
          "email" => "test@example.com",
          "metadata" => %{"user_id" => "123"}
        })
      end)

      # This should work but currently fails with Protocol.UndefinedError
      {:ok, response} =
        Client.create(:customers, %{
          email: "test@example.com",
          metadata: %{user_id: "123"}
        })

      assert response.body["id"] == "cus_test123"
      assert response.body["metadata"]["user_id"] == "123"
    end

    test "creates price with recurring nested parameter" do
      Req.Test.stub(PinStripe, fn conn ->
        # Verify recurring parameter is properly encoded
        assert conn.body_params["recurring[interval]"] == "month" or
                 conn.body_params["recurring"]["interval"] == "month"

        Req.Test.json(conn, %{
          "id" => "price_test123",
          "unit_amount" => 999,
          "currency" => "usd",
          "recurring" => %{"interval" => "month"}
        })
      end)

      # This should work but currently fails with Protocol.UndefinedError
      {:ok, response} =
        Client.create(:prices, %{
          product: "prod_123",
          unit_amount: 999,
          currency: "usd",
          recurring: %{interval: "month"}
        })

      assert response.body["id"] == "price_test123"
      assert response.body["recurring"]["interval"] == "month"
    end

    test "updates customer with nested metadata" do
      Req.Test.stub(PinStripe, fn conn ->
        assert conn.body_params["metadata[premium]"] == "true" or
                 conn.body_params["metadata"]["premium"] == "true"

        Req.Test.json(conn, %{
          "id" => "cus_test123",
          "metadata" => %{"premium" => "true"}
        })
      end)

      # This should work but currently fails with Protocol.UndefinedError
      {:ok, response} =
        Client.update("cus_test123", %{
          metadata: %{premium: "true"}
        })

      assert response.body["metadata"]["premium"] == "true"
    end

    test "creates customer with complex nested metadata" do
      Req.Test.stub(PinStripe, fn conn ->
        Req.Test.json(conn, %{
          "id" => "cus_test123",
          "metadata" => %{"user_id" => "123", "plan" => "premium"}
        })
      end)

      # Multiple nested keys
      {:ok, response} =
        Client.create(:customers, %{
          email: "test@example.com",
          metadata: %{
            user_id: "123",
            plan: "premium"
          }
        })

      assert response.body["metadata"]["user_id"] == "123"
      assert response.body["metadata"]["plan"] == "premium"
    end
  end

  describe "create with flat parameters" do
    test "creates customer without metadata (baseline - should work)" do
      Req.Test.stub(PinStripe, fn conn ->
        Req.Test.json(conn, %{
          "id" => "cus_test123",
          "email" => "test@example.com"
        })
      end)

      # This should work fine (no nested parameters)
      {:ok, response} =
        Client.create(:customers, %{
          email: "test@example.com",
          name: "Test User"
        })

      assert response.body["id"] == "cus_test123"
    end
  end
end
