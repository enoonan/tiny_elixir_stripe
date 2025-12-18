defmodule TinyElixirStripe.Client do
  @moduledoc """
  A minimal Stripe API client built on Req.

  This module provides a simple interface for interacting with the Stripe API,
  covering the most common operations while maintaining an escape hatch to Req
  for advanced use cases.

  ## Configuration

  Configure your Stripe API key in your application config:

      config :tiny_elixir_stripe,
        stripe_api_key: "sk_test_..."

  For testing, configure the client to use Req.Test:

      config :tiny_elixir_stripe,
        req_options: [plug: {Req.Test, TinyElixirStripe}]

  ## CRUD Operations

  The client supports standard CRUD operations with a consistent API:

  ### Read Operations

  Fetch individual resources by ID (string):

      Client.read("cus_123")
      # => {:ok, %Req.Response{body: %{"id" => "cus_123", ...}}}

  List resources by entity type (atom):

      Client.read(:customers, limit: 10)
      # => {:ok, %Req.Response{body: %{"object" => "list", "data" => [...]}}}

  ### Create Operations

  Create resources using entity type atoms:

      Client.create(:customers, %{email: "user@example.com"})
      # => {:ok, %Req.Response{body: %{"id" => "cus_new", ...}}}

  ### Update Operations

  Update resources by ID:

      Client.update("cus_123", %{name: "New Name"})
      # => {:ok, %Req.Response{body: %{"id" => "cus_123", "name" => "New Name"}}}

  ### Delete Operations

  Delete resources by ID:

      Client.delete("cus_123")
      # => {:ok, %Req.Response{body: %{"id" => "cus_123", "deleted" => true}}}

  ## Supported Entity Types

  The following entity types are supported (as atoms):

  - `:customers` - Customer objects
  - `:products` - Product objects
  - `:prices` - Price objects
  - `:subscriptions` - Subscription objects
  - `:invoices` - Invoice objects
  - `:events` - Event objects
  - `:checkout_sessions` - Checkout Session objects

  ## Error Handling

  All operations return `{:ok, response}` or `{:error, reason}` tuples:

      Client.read(:invalid_entity)
      # => {:error, :unrecognized_entity_type}

      # HTTP errors return the response with error details
      Client.read("cus_nonexistent")
      # => {:error, %Req.Response{status: 404, body: %{"error" => ...}}}

  ### Bang Functions

  Each CRUD function has a bang version (`read!/2`, `create!/3`, `update!/3`, `delete!/2`)
  that raises a `RuntimeError` instead of returning error tuples:

      # Raises on error
      response = Client.read!("cus_123")
      customer = response.body

      # Raises RuntimeError: "Unrecognized entity type: :invalid"
      Client.read!(:invalid)

      # Raises RuntimeError: "Request failed with status 404: ..."
      Client.read!("cus_nonexistent")

  ## ID Prefix Recognition

  The client automatically recognizes Stripe ID prefixes:

  - `cus_*` → `/customers/{id}`
  - `product_*` → `/products/{id}`
  - `price_*` → `/prices/{id}`
  - `sub_*` → `/subscriptions/{id}`
  - `inv_*` → `/invoices/{id}`
  - `evt_*` → `/events/{id}`
  - `cs_*` → `/checkout/sessions/{id}`

  ## Examples

      # Fetch a customer
      {:ok, response} = Client.read("cus_123")
      customer = response.body

      # List customers with pagination
      {:ok, response} = Client.read(:customers, limit: 10, starting_after: "cus_123")
      customers = response.body["data"]

      # Create a customer
      {:ok, response} = Client.create(:customers, %{
        email: "customer@example.com",
        name: "Jane Doe"
      })

      # Update a customer
      {:ok, response} = Client.update("cus_123", %{
        metadata: %{user_id: "12345"}
      })

      # Delete a customer
      {:ok, response} = Client.delete("cus_123")
  """

  def new(options \\ []) when is_list(options) do
    req_options = Application.get_env(:tiny_elixir_stripe, :req_options, [])

    Req.new(
      base_url: "https://api.stripe.com/v1",
      auth: {:bearer, Application.fetch_env!(:tiny_elixir_stripe, :stripe_api_key)}
    )
    |> Req.Request.append_request_steps(
      post: fn req ->
        with %{method: :get, body: <<_::binary>>} <- req do
          %{req | method: :post}
        end
      end
    )
    |> Req.merge(req_options)
    |> Req.merge(options)
  end

  @doc """
  Reads a resource by ID or lists resources by entity type.

  ## Parameters

    * `id_or_entity` - Either a string ID (e.g., `"cus_123"`) or an atom entity type (e.g., `:customers`)
    * `options` - Keyword list of options (e.g., query parameters for list operations)

  ## Examples

      # Fetch by ID
      iex> Req.Test.stub(TinyElixirStripe, fn conn ->
      ...>   Req.Test.json(conn, %{id: "cus_123", email: "test@example.com"})
      ...> end)
      iex> {:ok, response} = TinyElixirStripe.Client.read("cus_123")
      iex> response.body["id"]
      "cus_123"

      # List resources
      iex> Req.Test.stub(TinyElixirStripe, fn conn ->
      ...>   Req.Test.json(conn, %{object: "list", data: []})
      ...> end)
      iex> {:ok, response} = TinyElixirStripe.Client.read(:customers)
      iex> response.body["object"]
      "list"

      # Unrecognized entity type
      iex> TinyElixirStripe.Client.read(:invalid)
      {:error, :unrecognized_entity_type}
  """
  def read(id_or_entity, options \\ [])

  def read(id, options) when is_binary(id) do
    id |> parse_url() |> request(options)
  end

  def read(entity, options) when is_atom(entity) do
    case entity_to_path(entity) do
      {:ok, path} ->
        new(url: path)
        |> Req.merge(params: Enum.into(options, %{}))
        |> Req.request([])
        |> handle_response()

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Creates a new resource.

  ## Parameters

    * `entity` - Atom representing the entity type (e.g., `:customers`, `:products`)
    * `params` - Map of parameters for the resource
    * `options` - Keyword list of additional Req options

  ## Examples

      iex> Req.Test.stub(TinyElixirStripe, fn conn ->
      ...>   Req.Test.json(conn, %{id: "cus_new", email: "new@example.com"})
      ...> end)
      iex> {:ok, response} = TinyElixirStripe.Client.create(:customers, %{email: "new@example.com"})
      iex> response.body["id"]
      "cus_new"

      # Unrecognized entity type
      iex> TinyElixirStripe.Client.create(:invalid, %{})
      {:error, :unrecognized_entity_type}
  """
  def create(entity, params, options \\ []) when is_atom(entity) and is_map(params) do
    case entity_to_path(entity) do
      {:ok, path} ->
        new(url: path)
        |> Req.merge(form: params, method: :post)
        |> Req.request(options)
        |> handle_response()

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Updates an existing resource by ID.

  ## Parameters

    * `id` - String ID of the resource (e.g., `"cus_123"`)
    * `params` - Map of parameters to update
    * `options` - Keyword list of additional Req options

  ## Examples

      iex> Req.Test.stub(TinyElixirStripe, fn conn ->
      ...>   Req.Test.json(conn, %{id: "cus_123", name: "Updated"})
      ...> end)
      iex> {:ok, response} = TinyElixirStripe.Client.update("cus_123", %{name: "Updated"})
      iex> response.body["name"]
      "Updated"
  """
  def update(id, params, options \\ []) when is_binary(id) and is_map(params) do
    url = parse_url(id)

    new(url: url)
    |> Req.merge(form: params, method: :post)
    |> Req.request(options)
    |> handle_response()
  end

  @doc """
  Deletes a resource by ID.

  ## Parameters

    * `id` - String ID of the resource (e.g., `"cus_123"`)
    * `options` - Keyword list of additional Req options

  ## Examples

      iex> Req.Test.stub(TinyElixirStripe, fn conn ->
      ...>   Req.Test.json(conn, %{id: "cus_123", deleted: true})
      ...> end)
      iex> {:ok, response} = TinyElixirStripe.Client.delete("cus_123")
      iex> response.body["deleted"]
      true
  """
  def delete(id, options \\ []) when is_binary(id) do
    url = parse_url(id)

    new(url: url)
    |> Req.merge(method: :delete)
    |> Req.request(options)
    |> handle_response()
  end

  @doc """
  Reads a resource by ID or lists resources by entity type, raising on error.

  Similar to `read/2` but raises a `RuntimeError` on error instead of returning an error tuple.

  ## Parameters

    * `id_or_entity` - Either a string ID or an atom entity type
    * `options` - Keyword list of options

  ## Examples

      iex> Req.Test.stub(TinyElixirStripe, fn conn ->
      ...>   Req.Test.json(conn, %{id: "cus_123"})
      ...> end)
      iex> response = TinyElixirStripe.Client.read!("cus_123")
      iex> response.body["id"]
      "cus_123"
  """
  def read!(id_or_entity, options \\ []) do
    case read(id_or_entity, options) do
      {:ok, response} ->
        response

      {:error, :unrecognized_entity_type} ->
        raise "Unrecognized entity type: #{inspect(id_or_entity)}"

      {:error, %Req.Response{status: status} = response} ->
        raise "Request failed with status #{status}: #{inspect(response.body)}"

      {:error, reason} ->
        raise "Request failed: #{inspect(reason)}"
    end
  end

  @doc """
  Creates a new resource, raising on error.

  Similar to `create/3` but raises a `RuntimeError` on error instead of returning an error tuple.

  ## Parameters

    * `entity` - Atom representing the entity type
    * `params` - Map of parameters for the resource
    * `options` - Keyword list of additional Req options

  ## Examples

      iex> Req.Test.stub(TinyElixirStripe, fn conn ->
      ...>   Req.Test.json(conn, %{id: "cus_new"})
      ...> end)
      iex> response = TinyElixirStripe.Client.create!(:customers, %{email: "test@example.com"})
      iex> response.body["id"]
      "cus_new"
  """
  def create!(entity, params, options \\ []) do
    case create(entity, params, options) do
      {:ok, response} ->
        response

      {:error, :unrecognized_entity_type} ->
        raise "Unrecognized entity type: #{inspect(entity)}"

      {:error, %Req.Response{status: status} = response} ->
        raise "Request failed with status #{status}: #{inspect(response.body)}"

      {:error, reason} ->
        raise "Request failed: #{inspect(reason)}"
    end
  end

  @doc """
  Updates an existing resource by ID, raising on error.

  Similar to `update/3` but raises a `RuntimeError` on error instead of returning an error tuple.

  ## Parameters

    * `id` - String ID of the resource
    * `params` - Map of parameters to update
    * `options` - Keyword list of additional Req options

  ## Examples

      iex> Req.Test.stub(TinyElixirStripe, fn conn ->
      ...>   Req.Test.json(conn, %{id: "cus_123", name: "Updated"})
      ...> end)
      iex> response = TinyElixirStripe.Client.update!("cus_123", %{name: "Updated"})
      iex> response.body["name"]
      "Updated"
  """
  def update!(id, params, options \\ []) do
    case update(id, params, options) do
      {:ok, response} ->
        response

      {:error, %Req.Response{status: status} = response} ->
        raise "Request failed with status #{status}: #{inspect(response.body)}"

      {:error, reason} ->
        raise "Request failed: #{inspect(reason)}"
    end
  end

  @doc """
  Deletes a resource by ID, raising on error.

  Similar to `delete/2` but raises a `RuntimeError` on error instead of returning an error tuple.

  ## Parameters

    * `id` - String ID of the resource
    * `options` - Keyword list of additional Req options

  ## Examples

      iex> Req.Test.stub(TinyElixirStripe, fn conn ->
      ...>   Req.Test.json(conn, %{id: "cus_123", deleted: true})
      ...> end)
      iex> response = TinyElixirStripe.Client.delete!("cus_123")
      iex> response.body["deleted"]
      true
  """
  def delete!(id, options \\ []) do
    case delete(id, options) do
      {:ok, response} ->
        response

      {:error, %Req.Response{status: status} = response} ->
        raise "Request failed with status #{status}: #{inspect(response.body)}"

      {:error, reason} ->
        raise "Request failed: #{inspect(reason)}"
    end
  end

  def request(url, options \\ []) do
    new(url: parse_url(url))
    |> Req.request(options)
    |> handle_response()
  end

  defp handle_response(result) do
    case result do
      {:ok, %Req.Response{status: status} = response} when status >= 200 and status < 300 ->
        {:ok, response}

      {:ok, %Req.Response{status: status} = response} when status >= 400 ->
        {:error, response}

      other ->
        other
    end
  end

  def request!(url, options \\ []), do: Req.request!(new(url: parse_url(url)), options)

  defp parse_url("product_" <> _ = id), do: "/products/#{id}"
  defp parse_url("price_" <> _ = id), do: "/prices/#{id}"
  defp parse_url("sub_" <> _ = id), do: "/subscriptions/#{id}"
  defp parse_url("cus_" <> _ = id), do: "/customers/#{id}"
  defp parse_url("cs_" <> _ = id), do: "/checkout/sessions/#{id}"
  defp parse_url("inv_" <> _ = id), do: "/invoices/#{id}"
  defp parse_url("evt_" <> _ = id), do: "/events/#{id}"
  defp parse_url(url) when is_binary(url), do: url

  defp entity_to_path(:customers), do: {:ok, "/customers"}
  defp entity_to_path(:products), do: {:ok, "/products"}
  defp entity_to_path(:prices), do: {:ok, "/prices"}
  defp entity_to_path(:subscriptions), do: {:ok, "/subscriptions"}
  defp entity_to_path(:invoices), do: {:ok, "/invoices"}
  defp entity_to_path(:events), do: {:ok, "/events"}
  defp entity_to_path(:checkout_sessions), do: {:ok, "/checkout/sessions"}
  defp entity_to_path(_), do: {:error, :unrecognized_entity_type}
end
