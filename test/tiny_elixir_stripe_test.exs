defmodule TinyElixirStripeTest do
  use ExUnit.Case, async: true
  doctest TinyElixirStripe
  doctest TinyElixirStripe.Client

  alias TinyElixirStripe.Client

  setup do
    # Set test environment for stripe_api_key and plug
    Application.put_env(:tiny_elixir_stripe, :stripe_api_key, "sk_test_123")
    Application.put_env(:tiny_elixir_stripe, :req_options, plug: {Req.Test, TinyElixirStripe})

    on_exit(fn ->
      Application.delete_env(:tiny_elixir_stripe, :stripe_api_key)
      Application.delete_env(:tiny_elixir_stripe, :req_options)
    end)

    :ok
  end

  describe "read/2" do
    test "fetches a customer by ID successfully" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        Req.Test.json(conn, %{id: "cus_123", email: "test@example.com"})
      end)

      result = Client.read("cus_123")

      assert {:ok, %{body: %{"id" => "cus_123"}}} = result
    end

    test "handles customer not found" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{error: %{message: "Not found"}})
      end)

      result = Client.read("cus_404")

      assert {:error, %{status: 404, body: %{"error" => %{"message" => "Not found"}}}} = result
    end

    test "fetches a product by deriving entity type from ID" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        Req.Test.json(conn, %{id: "product_123", name: "Test Product"})
      end)

      result = Client.read("product_123")

      assert {:ok, %{body: %{"id" => "product_123"}}} = result
    end

    test "lists customers when given :customers atom" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        assert conn.request_path == "/v1/customers"
        assert conn.method == "GET"

        Req.Test.json(conn, %{
          object: "list",
          data: [
            %{id: "cus_1", email: "user1@example.com"},
            %{id: "cus_2", email: "user2@example.com"}
          ]
        })
      end)

      result = Client.read(:customers)

      assert {:ok, %{body: %{"object" => "list", "data" => data}}} = result
      assert length(data) == 2
    end

    test "lists products when given :products atom" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        assert conn.request_path == "/v1/products"

        Req.Test.json(conn, %{
          object: "list",
          data: [%{id: "product_1", name: "Product 1"}]
        })
      end)

      result = Client.read(:products)

      assert {:ok, %{body: %{"object" => "list"}}} = result
    end

    test "returns error for unrecognized entity type" do
      result = Client.read(:invalid_entity)

      assert {:error, :unrecognized_entity_type} = result
    end

    test "lists with query parameters" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        assert conn.request_path == "/v1/customers"
        # Query params would be in conn.query_params
        Req.Test.json(conn, %{object: "list", data: []})
      end)

      result = Client.read(:customers, limit: 10)

      assert {:ok, %{body: %{"object" => "list"}}} = result
    end
  end

  describe "create/3" do
    test "creates a customer successfully with params" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/customers"
        Req.Test.json(conn, %{id: "cus_new", email: "test@example.com"})
      end)

      result = Client.create(:customers, %{email: "test@example.com", name: "Test User"})

      assert {:ok, %{body: %{"id" => "cus_new"}}} = result
    end

    test "handles validation errors on create" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{error: %{message: "Invalid email"}})
      end)

      result = Client.create(:customers, %{email: "invalid"})

      assert {:error, %{status: 400, body: %{"error" => %{"message" => "Invalid email"}}}} =
               result
    end

    test "creates a product with atom entity type" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        assert conn.request_path == "/v1/products"
        Req.Test.json(conn, %{id: "product_new", name: "Test Product"})
      end)

      result = Client.create(:products, %{name: "Test Product"})

      assert {:ok, %{body: %{"id" => "product_new"}}} = result
    end

    test "returns error for unrecognized entity type" do
      result = Client.create(:invalid_entity, %{foo: "bar"})

      assert {:error, :unrecognized_entity_type} = result
    end
  end

  describe "update/3" do
    test "updates a customer successfully with params" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        assert conn.method == "POST"
        Req.Test.json(conn, %{id: "cus_123", name: "Updated Name"})
      end)

      result = Client.update("cus_123", %{name: "Updated Name"})

      assert {:ok, %{body: %{"id" => "cus_123", "name" => "Updated Name"}}} = result
    end

    test "handles update errors" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{error: %{message: "Customer not found"}})
      end)

      result = Client.update("cus_404", %{name: "Test"})

      assert {:error, %{status: 404}} = result
    end
  end

  describe "delete/2" do
    test "deletes a customer successfully" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        assert conn.method == "DELETE"
        Req.Test.json(conn, %{id: "cus_123", deleted: true})
      end)

      result = Client.delete("cus_123")

      assert {:ok, %{body: %{"deleted" => true}}} = result
    end

    test "handles delete errors" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{error: %{message: "Not found"}})
      end)

      result = Client.delete("cus_404")

      assert {:error, %{status: 404}} = result
    end
  end

  describe "read!/2" do
    test "fetches a customer successfully and returns response" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        Req.Test.json(conn, %{id: "cus_123", email: "test@example.com"})
      end)

      response = Client.read!("cus_123")

      assert response.body["id"] == "cus_123"
    end

    test "raises on unrecognized entity type" do
      assert_raise RuntimeError, "Unrecognized entity type: :invalid", fn ->
        Client.read!(:invalid)
      end
    end

    test "raises on HTTP error" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{error: %{message: "Not found"}})
      end)

      assert_raise RuntimeError, ~r/Request failed with status 404/, fn ->
        Client.read!("cus_404")
      end
    end
  end

  describe "create!/3" do
    test "creates a customer successfully and returns response" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        Req.Test.json(conn, %{id: "cus_new", email: "test@example.com"})
      end)

      response = Client.create!(:customers, %{email: "test@example.com"})

      assert response.body["id"] == "cus_new"
    end

    test "raises on unrecognized entity type" do
      assert_raise RuntimeError, "Unrecognized entity type: :invalid", fn ->
        Client.create!(:invalid, %{})
      end
    end

    test "raises on validation error" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{error: %{message: "Invalid email"}})
      end)

      assert_raise RuntimeError, ~r/Request failed with status 400/, fn ->
        Client.create!(:customers, %{email: "invalid"})
      end
    end
  end

  describe "update!/3" do
    test "updates a customer successfully and returns response" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        Req.Test.json(conn, %{id: "cus_123", name: "Updated"})
      end)

      response = Client.update!("cus_123", %{name: "Updated"})

      assert response.body["name"] == "Updated"
    end

    test "raises on HTTP error" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{error: %{message: "Not found"}})
      end)

      assert_raise RuntimeError, ~r/Request failed with status 404/, fn ->
        Client.update!("cus_404", %{name: "Test"})
      end
    end
  end

  describe "delete!/2" do
    test "deletes a customer successfully and returns response" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        Req.Test.json(conn, %{id: "cus_123", deleted: true})
      end)

      response = Client.delete!("cus_123")

      assert response.body["deleted"] == true
    end

    test "raises on HTTP error" do
      Req.Test.stub(TinyElixirStripe, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{error: %{message: "Not found"}})
      end)

      assert_raise RuntimeError, ~r/Request failed with status 404/, fn ->
        Client.delete!("cus_404")
      end
    end
  end
end
