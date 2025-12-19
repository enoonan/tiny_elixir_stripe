defmodule PinStripe.Test.Mock do
  @moduledoc """
  Test mocking utilities for PinStripe, wrapping Req.Test with sensible defaults.

  This module provides a thin wrapper around `Req.Test` with two main benefits:

  1. **Single Namespace**: All PinStripe testing utilities under `PinStripe.Test.*`
  2. **Sensible Defaults**: Functions default to using `PinStripe` as the stub name

  ## Relationship to Req.Test

  This module delegates core functionality to `Req.Test`. For advanced use cases or
  detailed documentation, refer to the [Req.Test documentation](https://hexdocs.pm/req/Req.Test.html).

  The main functions are:

  - `stub/1` and `stub/2` - Create request stubs
  - `expect/1`, `expect/2`, and `expect/3` - Create request expectations
  - `allow/2` and `allow/3` - Allow other processes to use stubs/mocks
  - `json/2` - Create JSON responses (Stripe API returns JSON)
  - `transport_error/2` - Simulate network errors

  ## High-Level Stripe Helpers

  For common Stripe operations, use these helpers that automatically handle URL resolution:

  - `stub_read/2` - Stub read/list operations
  - `stub_create/2` - Stub create operations
  - `stub_update/2` - Stub update operations
  - `stub_delete/2` - Stub delete operations
  - `stub_error/3` - Stub error responses

  ## Setup

  Configure your test environment to use Req.Test:

      # config/test.exs
      config :pin_stripe,
        stripe_api_key: "sk_test_...",
        req_options: [plug: {Req.Test, PinStripe}]

  ## High-Level Helpers (Recommended)

  The easiest way to stub PinStripe operations is to use the high-level helper functions
  that mirror `PinStripe.Client` operations. These automatically handle URL resolution
  and HTTP method matching:

      test "reads a customer using stub_read" do
        Mock.stub_read("cus_123", %{"id" => "cus_123", "email" => "test@example.com"})

        {:ok, response} = Client.read("cus_123")
        assert response.body["email"] == "test@example.com"
      end

      test "creates a customer using stub_create" do
        Mock.stub_create(:customers, %{"id" => "cus_new", "email" => "new@example.com"})

        {:ok, response} = Client.create(:customers, %{email: "new@example.com"})
        assert response.body["id"] == "cus_new"
      end

      test "updates a customer using stub_update" do
        Mock.stub_update("cus_123", %{"id" => "cus_123", "name" => "Updated Name"})

        {:ok, response} = Client.update("cus_123", %{name: "Updated Name"})
        assert response.body["name"] == "Updated Name"
      end

      test "deletes a customer using stub_delete" do
        Mock.stub_delete("cus_123", %{"id" => "cus_123", "deleted" => true})

        {:ok, response} = Client.delete("cus_123")
        assert response.body["deleted"] == true
      end

      test "stubs errors using stub_error" do
        Mock.stub_error("cus_nonexistent", 404, %{
          "error" => %{"code" => "resource_missing"}
        })

        {:error, response} = Client.read("cus_nonexistent")
        assert response.status == 404
      end

  These helpers work seamlessly with fixtures:

      test "uses fixtures with helpers" do
        customer = Fixtures.load(:customer)
        Mock.stub_read("cus_123", customer)

        error = Fixtures.load(:error_404)
        Mock.stub_error("cus_missing", 404, error)
      end

  ## Basic Usage with Raw Data (Lower-Level)

  The simplest approach is to stub responses with inline data:

      test "reads a customer" do
        Mock.stub(fn conn ->
          if conn.method == "GET" and conn.request_path == "/v1/customers/cus_123" do
            Mock.json(conn, %{"id" => "cus_123", "email" => "test@example.com"})
          else
            conn
          end
        end)

        {:ok, response} = Client.read("cus_123")
        assert response.body["email"] == "test@example.com"
      end

      test "creates a customer" do
        Mock.stub(fn conn ->
          if conn.method == "POST" and conn.request_path == "/v1/customers" do
            Mock.json(conn, %{"id" => "cus_new", "email" => "new@example.com"})
          else
            conn
          end
        end)

        {:ok, response} = Client.create(:customers, %{email: "new@example.com"})
        assert response.body["id"] == "cus_new"
      end

      test "lists customers" do
        Mock.stub(fn conn ->
          if conn.method == "GET" and conn.request_path == "/v1/customers" do
            Mock.json(conn, %{
              "object" => "list",
              "data" => [
                %{"id" => "cus_1", "email" => "user1@example.com"},
                %{"id" => "cus_2", "email" => "user2@example.com"}
              ],
              "has_more" => false
            })
          else
            conn
          end
        end)

        {:ok, response} = Client.read(:customers)
        assert length(response.body["data"]) == 2
      end

  ## Using Fixtures

  For more realistic test data, use `PinStripe.Test.Fixtures` to load fixture files:

      test "reads a customer using fixture" do
        Mock.stub(fn conn ->
          if conn.method == "GET" and conn.request_path == "/v1/customers/cus_123" do
            customer = Fixtures.load(:customer)
            Mock.json(conn, customer)
          else
            conn
          end
        end)

        {:ok, response} = Client.read("cus_123")
        assert response.body["object"] == "customer"
      end

      test "reads a customer with custom fixture data" do
        Mock.stub(fn conn ->
          if conn.method == "GET" and conn.request_path == "/v1/customers/cus_123" do
            customer = Fixtures.load(:customer, email: "custom@example.com", name: "Custom Name")
            Mock.json(conn, customer)
          else
            conn
          end
        end)

        {:ok, response} = Client.read("cus_123")
        assert response.body["email"] == "custom@example.com"
        assert response.body["name"] == "Custom Name"
      end

  ## Stubbing Errors

  Use `Plug.Conn.put_status/2` to return error responses:

      test "handles 404 error" do
        Mock.stub(fn conn ->
          if conn.method == "GET" and conn.request_path == "/v1/customers/cus_nonexistent" do
            conn
            |> Plug.Conn.put_status(404)
            |> Mock.json(%{
              "error" => %{
                "type" => "invalid_request_error",
                "code" => "resource_missing",
                "message" => "No such customer: cus_nonexistent"
              }
            })
          else
            conn
          end
        end)

        assert {:error, %{status: 404}} = Client.read("cus_nonexistent")
      end

      test "handles error using fixture" do
        Mock.stub(fn conn ->
          if conn.method == "POST" and conn.request_path == "/v1/customers" do
            error = Fixtures.load(:error_400)
            conn
            |> Plug.Conn.put_status(400)
            |> Mock.json(error)
          else
            conn
          end
        end)

        {:error, response} = Client.create(:customers, %{})
        assert response.status == 400
        assert response.body["error"]["code"] == "parameter_invalid_empty"
      end

  ## Pattern Matching on Multiple Requests

  You can handle multiple request patterns in a single stub:

      test "handles multiple operations" do
        Mock.stub(fn conn ->
          case {conn.method, conn.request_path} do
            {"GET", "/v1/customers/" <> id} ->
              Mock.json(conn, %{"id" => id, "email" => "\#{id}@example.com"})

            {"POST", "/v1/customers"} ->
              Mock.json(conn, %{"id" => "cus_new", "email" => "new@example.com"})

            {"DELETE", "/v1/customers/" <> id} ->
              Mock.json(conn, %{"id" => id, "deleted" => true, "object" => "customer"})

            _ ->
              conn
          end
        end)

        {:ok, read_response} = Client.read("cus_123")
        assert read_response.body["id"] == "cus_123"

        {:ok, create_response} = Client.create(:customers, %{email: "new@example.com"})
        assert create_response.body["id"] == "cus_new"

        {:ok, delete_response} = Client.delete("cus_123")
        assert delete_response.body["deleted"] == true
      end

  ## Available Fixtures

  See `PinStripe.Test.Fixtures` for the full list of available fixtures:

  - `:customer` - A Stripe customer object
  - `:charge` - A Stripe charge object
  - `:payment_intent` - A Stripe payment intent object
  - `:refund` - A Stripe refund object
  - `:error_400`, `:error_401`, `:error_403`, `:error_404`, etc. - Various error responses

  All fixtures can be customized with keyword options that override specific fields.
  """

  @doc """
  Sends a JSON response. See `Req.Test.json/2`.

  The Stripe API returns JSON for all responses, so this is the primary
  response helper you'll use in tests.
  """
  defdelegate json(conn, data), to: Req.Test

  @doc """
  Simulates a network transport error. See `Req.Test.transport_error/2`.

  Useful for testing network failure scenarios like connection timeouts or refused connections.
  """
  defdelegate transport_error(conn, reason), to: Req.Test

  @doc """
  Creates a request stub with the given plug.

  Defaults to using `PinStripe` as the stub name. For custom names, use `stub/2`.

  ## Examples

      iex> alias PinStripe.Test.Mock
      iex> Mock.stub(fn conn ->
      ...>   Mock.json(conn, %{"id" => "cus_123"})
      ...> end)
      :ok
      iex> {:ok, response} = PinStripe.Client.read("cus_123")
      iex> response.body["id"]
      "cus_123"
  """
  def stub(plug) when is_function(plug), do: Req.Test.stub(PinStripe, plug)

  @doc """
  Creates a request stub with the given plug and custom name.

  See `Req.Test.stub/2` for full documentation.

  ## Examples

      test "stubs with custom name" do
        Mock.stub(fn conn ->
          Mock.json(conn, %{id: "test"})
        end, :custom_name)
      end
  """
  def stub(plug, name) when is_function(plug), do: Req.Test.stub(name, plug)

  @doc """
  Creates a request expectation expected to be called once.

  Defaults to using `PinStripe` as the stub name. For custom counts or names, use `expect/2` or `expect/3`.

  ## Examples

      test "expects one request" do
        Mock.expect(fn conn ->
          Mock.json(conn, %{id: "cus_123"})
        end)

        {:ok, _} = Client.read("cus_123")
      end
  """
  def expect(plug) when is_function(plug), do: Req.Test.expect(PinStripe, 1, plug)

  @doc """
  Creates a request expectation with the given plug and count.

  Defaults to using `PinStripe` as the stub name. For custom names, use `expect/3`.

  ## Examples

      test "expects multiple requests" do
        Mock.expect(fn conn ->
          Mock.json(conn, %{id: "test"})
        end, 2)

        {:ok, _} = Client.read("test_123")
        {:ok, _} = Client.read("test_456")
      end
  """
  def expect(plug, count) when is_function(plug) and is_integer(count),
    do: Req.Test.expect(PinStripe, count, plug)

  @doc """
  Creates a request expectation with the given plug, count, and name.

  See `Req.Test.expect/3` for full documentation.

  ## Examples

      test "expects requests with custom name" do
        Mock.expect(fn conn ->
          Mock.json(conn, %{id: "test"})
        end, 2, :custom)
      end
  """
  def expect(plug, count, name) when is_function(plug) and is_integer(count),
    do: Req.Test.expect(name, count, plug)

  @doc """
  Allows the process `pid` to use stubs defined by `owner`.

  Defaults to using `PinStripe` as the stub name. For custom names, use `allow/3`.

  See `Req.Test.allow/3` for full documentation on allowances and concurrent testing.

  ## Examples

      test "allows spawned process to use stubs" do
        {:ok, pid} = start_supervised(MyWorker)

        Mock.stub(fn conn ->
          Mock.json(conn, %{id: "test"})
        end)

        Mock.allow(self(), pid)

        # Now pid can use the stub
      end
  """
  def allow(owner, pid) when is_pid(owner) and is_pid(pid), do: allow(PinStripe, owner, pid)

  @doc """
  Allows the process `pid` to use stubs defined by `owner` for the given `name`.

  See `Req.Test.allow/3` for full documentation.
  """
  def allow(name, owner, pid), do: Req.Test.allow(name, owner, pid)

  @doc """
  Stubs a read operation for the given ID or entity type.

  This is a convenience wrapper around `stub/1` that automatically handles:
  - URL resolution via `PinStripe.Client.parse_url/1` (for string IDs)
  - Entity type to path conversion via `PinStripe.Client.entity_to_path/1` (for atom entity types)
  - Proper HTTP method matching (GET)

  ## Parameters

    * `id_or_entity` - Either a string ID (e.g., `"cus_123"`) or an atom entity type (e.g., `:customers`)
    * `response_data` - Map of data to return in the JSON response

  ## Examples

      # Stub reading a customer by ID
      iex> PinStripe.Test.Mock.stub_read("cus_123", %{"id" => "cus_123", "email" => "test@example.com"})
      :ok
      iex> {:ok, response} = PinStripe.Client.read("cus_123")
      iex> response.body["email"]
      "test@example.com"

      # Stub reading a product by ID
      iex> PinStripe.Test.Mock.stub_read("product_abc", %{"id" => "product_abc", "name" => "Widget"})
      :ok
      iex> {:ok, response} = PinStripe.Client.read("product_abc")
      iex> response.body["name"]
      "Widget"

      # Stub listing customers by entity type
      iex> PinStripe.Test.Mock.stub_read(:customers, %{
      ...>   "object" => "list",
      ...>   "data" => [%{"id" => "cus_1"}],
      ...>   "has_more" => false
      ...> })
      :ok
      iex> {:ok, response} = PinStripe.Client.read(:customers)
      iex> response.body["object"]
      "list"
  """
  def stub_read(id_or_entity, response_data) when is_binary(id_or_entity) do
    path = PinStripe.Client.parse_url(id_or_entity)

    stub(fn conn ->
      if conn.method == "GET" and conn.request_path == "/v1#{path}" do
        json(conn, response_data)
      else
        conn
      end
    end)
  end

  def stub_read(entity, response_data) when is_atom(entity) do
    path = get_entity_path!(entity)

    stub(fn conn ->
      if conn.method == "GET" and conn.request_path == "/v1#{path}" do
        json(conn, response_data)
      else
        conn
      end
    end)
  end

  @doc """
  Stubs a create operation for the given entity type.

  This is a convenience wrapper around `stub/1` that automatically handles:
  - Entity type to path conversion via `PinStripe.Client.entity_to_path/1`
  - Proper HTTP method matching (POST)

  ## Parameters

    * `entity` - Atom representing the entity type (e.g., `:customers`, `:products`)
    * `response_data` - Map of data to return in the JSON response

  ## Examples

      # Stub creating a customer
      iex> PinStripe.Test.Mock.stub_create(:customers, %{"id" => "cus_new", "email" => "new@example.com"})
      :ok
      iex> {:ok, response} = PinStripe.Client.create(:customers, %{email: "new@example.com"})
      iex> response.body["id"]
      "cus_new"

      # Stub creating a product
      iex> PinStripe.Test.Mock.stub_create(:products, %{"id" => "product_new", "name" => "Widget"})
      :ok
      iex> {:ok, response} = PinStripe.Client.create(:products, %{name: "Widget"})
      iex> response.body["name"]
      "Widget"
  """
  def stub_create(entity, response_data) when is_atom(entity) do
    path = get_entity_path!(entity)

    stub(fn conn ->
      if conn.method == "POST" and conn.request_path == "/v1#{path}" do
        json(conn, response_data)
      else
        conn
      end
    end)
  end

  @doc """
  Stubs an update operation for the given ID.

  This is a convenience wrapper around `stub/1` that automatically handles:
  - URL resolution via `PinStripe.Client.parse_url/1`
  - Proper HTTP method matching (POST for updates in Stripe API)

  ## Parameters

    * `id` - String ID of the resource (e.g., `"cus_123"`)
    * `response_data` - Map of data to return in the JSON response

  ## Examples

      # Stub updating a customer
      iex> PinStripe.Test.Mock.stub_update("cus_123", %{"id" => "cus_123", "name" => "Updated Name"})
      :ok
      iex> {:ok, response} = PinStripe.Client.update("cus_123", %{name: "Updated Name"})
      iex> response.body["name"]
      "Updated Name"

      # Stub updating a subscription
      iex> PinStripe.Test.Mock.stub_update("sub_xyz", %{"id" => "sub_xyz", "status" => "canceled"})
      :ok
      iex> {:ok, response} = PinStripe.Client.update("sub_xyz", %{status: "canceled"})
      iex> response.body["status"]
      "canceled"
  """
  def stub_update(id, response_data) when is_binary(id) do
    path = PinStripe.Client.parse_url(id)

    stub(fn conn ->
      if conn.method == "POST" and conn.request_path == "/v1#{path}" do
        json(conn, response_data)
      else
        conn
      end
    end)
  end

  @doc """
  Stubs a delete operation for the given ID.

  This is a convenience wrapper around `stub/1` that automatically handles:
  - URL resolution via `PinStripe.Client.parse_url/1`
  - Proper HTTP method matching (DELETE)

  ## Parameters

    * `id` - String ID of the resource (e.g., `"cus_123"`)
    * `response_data` - Map of data to return in the JSON response (typically includes `"deleted" => true`)

  ## Examples

      # Stub deleting a customer
      iex> PinStripe.Test.Mock.stub_delete("cus_123", %{
      ...>   "id" => "cus_123",
      ...>   "deleted" => true,
      ...>   "object" => "customer"
      ...> })
      :ok
      iex> {:ok, response} = PinStripe.Client.delete("cus_123")
      iex> response.body["deleted"]
      true

      # Stub deleting a product
      iex> PinStripe.Test.Mock.stub_delete("product_abc", %{"id" => "product_abc", "deleted" => true})
      :ok
      iex> {:ok, response} = PinStripe.Client.delete("product_abc")
      iex> response.body["deleted"]
      true
  """
  def stub_delete(id, response_data) when is_binary(id) do
    path = PinStripe.Client.parse_url(id)

    stub(fn conn ->
      if conn.method == "DELETE" and conn.request_path == "/v1#{path}" do
        json(conn, response_data)
      else
        conn
      end
    end)
  end

  @doc """
  Stubs an error response for the given ID, entity type, or any request.

  This is a convenience wrapper around `stub/1` that automatically handles:
  - URL resolution for string IDs via `PinStripe.Client.parse_url/1`
  - Entity type to path conversion for atom entity types
  - Setting the appropriate HTTP status code
  - Matching any request when `:any` is passed

  ## Parameters

    * `id_entity_or_any` - Either a string ID (e.g., `"cus_123"`), an atom entity type (e.g., `:customers`), or `:any` to match all requests
    * `status` - HTTP status code (e.g., `404`, `400`, `401`)
    * `error_data` - Map of error data to return in the JSON response

  ## Examples

      # Stub a 404 error for a specific customer
      iex> PinStripe.Test.Mock.stub_error("cus_nonexistent", 404, %{
      ...>   "error" => %{
      ...>     "type" => "invalid_request_error",
      ...>     "code" => "resource_missing"
      ...>   }
      ...> })
      :ok
      iex> {:error, response} = PinStripe.Client.read("cus_nonexistent")
      iex> response.status
      404

      # Stub a 400 error for customer creation
      iex> PinStripe.Test.Mock.stub_error(:customers, 400, %{
      ...>   "error" => %{"code" => "parameter_invalid_empty"}
      ...> })
      :ok
      iex> {:error, response} = PinStripe.Client.create(:customers, %{})
      iex> response.status
      400

      # Stub an error for any request
      iex> PinStripe.Test.Mock.stub_error(:any, 401, %{"error" => %{"message" => "Invalid API key"}})
      :ok
      iex> {:error, response} = PinStripe.Client.read("cus_123")
      iex> response.status
      401
  """
  def stub_error(id, status, error_data) when is_binary(id) and is_integer(status) do
    path = PinStripe.Client.parse_url(id)

    stub(fn conn ->
      if conn.request_path == "/v1#{path}" do
        conn
        |> Plug.Conn.put_status(status)
        |> json(error_data)
      else
        conn
      end
    end)
  end

  def stub_error(:any, status, error_data) when is_integer(status) do
    stub(fn conn ->
      conn
      |> Plug.Conn.put_status(status)
      |> json(error_data)
    end)
  end

  def stub_error(entity, status, error_data) when is_atom(entity) and is_integer(status) do
    path = get_entity_path!(entity)

    stub(fn conn ->
      if conn.request_path == "/v1#{path}" do
        conn
        |> Plug.Conn.put_status(status)
        |> json(error_data)
      else
        conn
      end
    end)
  end

  # Private helper to get entity path and raise on error
  defp get_entity_path!(entity) do
    case PinStripe.Client.entity_to_path(entity) do
      {:ok, path} ->
        path

      {:error, :unrecognized_entity_type} ->
        raise ArgumentError, "Unrecognized entity type: #{inspect(entity)}"
    end
  end
end
