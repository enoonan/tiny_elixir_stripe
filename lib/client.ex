defmodule PinStripe.Client do
  @moduledoc """
  A minimal Stripe API client built on Req.

  This module provides a simple interface for interacting with the Stripe API,
  covering the most common operations while maintaining an escape hatch to Req
  for advanced use cases.

  ## Configuration

  Configure your Stripe API key in your application config:

      config :pin_stripe,
        stripe_api_key: "sk_test_..."

  For testing, configure the client to use Req.Test:

      config :pin_stripe,
        req_options: [plug: {Req.Test, PinStripe}]

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
    req_options = Application.get_env(:pin_stripe, :req_options, [])

    Req.new(
      base_url: "https://api.stripe.com/v1",
      auth: {:bearer, Application.fetch_env!(:pin_stripe, :stripe_api_key)}
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
      iex> Req.Test.stub(PinStripe, fn conn ->
      ...>   Req.Test.json(conn, %{id: "cus_123", email: "test@example.com"})
      ...> end)
      iex> {:ok, response} = PinStripe.Client.read("cus_123")
      iex> response.body["id"]
      "cus_123"

      # List resources
      iex> Req.Test.stub(PinStripe, fn conn ->
      ...>   Req.Test.json(conn, %{object: "list", data: []})
      ...> end)
      iex> {:ok, response} = PinStripe.Client.read(:customers)
      iex> response.body["object"]
      "list"

      # Unrecognized entity type
      iex> PinStripe.Client.read(:invalid)
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

      iex> Req.Test.stub(PinStripe, fn conn ->
      ...>   Req.Test.json(conn, %{id: "cus_new", email: "new@example.com"})
      ...> end)
      iex> {:ok, response} = PinStripe.Client.create(:customers, %{email: "new@example.com"})
      iex> response.body["id"]
      "cus_new"

      # Unrecognized entity type
      iex> PinStripe.Client.create(:invalid, %{})
      {:error, :unrecognized_entity_type}
  """
  def create(entity, params, options \\ []) when is_atom(entity) and is_map(params) do
    case entity_to_path(entity) do
      {:ok, path} ->
        encoded_params = encode_nested_params(params)

        new(url: path)
        |> Req.merge(body: encoded_params, method: :post)
        |> Req.Request.put_header("content-type", "application/x-www-form-urlencoded")
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

      iex> Req.Test.stub(PinStripe, fn conn ->
      ...>   Req.Test.json(conn, %{id: "cus_123", name: "Updated"})
      ...> end)
      iex> {:ok, response} = PinStripe.Client.update("cus_123", %{name: "Updated"})
      iex> response.body["name"]
      "Updated"
  """
  def update(id, params, options \\ []) when is_binary(id) and is_map(params) do
    url = parse_url(id)
    encoded_params = encode_nested_params(params)

    new(url: url)
    |> Req.merge(body: encoded_params, method: :post)
    |> Req.Request.put_header("content-type", "application/x-www-form-urlencoded")
    |> Req.request(options)
    |> handle_response()
  end

  @doc """
  Deletes a resource by ID.

  ## Parameters

    * `id` - String ID of the resource (e.g., `"cus_123"`)
    * `options` - Keyword list of additional Req options

  ## Examples

      iex> Req.Test.stub(PinStripe, fn conn ->
      ...>   Req.Test.json(conn, %{id: "cus_123", deleted: true})
      ...> end)
      iex> {:ok, response} = PinStripe.Client.delete("cus_123")
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

      iex> Req.Test.stub(PinStripe, fn conn ->
      ...>   Req.Test.json(conn, %{id: "cus_123"})
      ...> end)
      iex> response = PinStripe.Client.read!("cus_123")
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

      iex> Req.Test.stub(PinStripe, fn conn ->
      ...>   Req.Test.json(conn, %{id: "cus_new"})
      ...> end)
      iex> response = PinStripe.Client.create!(:customers, %{email: "test@example.com"})
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

      iex> Req.Test.stub(PinStripe, fn conn ->
      ...>   Req.Test.json(conn, %{id: "cus_123", name: "Updated"})
      ...> end)
      iex> response = PinStripe.Client.update!("cus_123", %{name: "Updated"})
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

      iex> Req.Test.stub(PinStripe, fn conn ->
      ...>   Req.Test.json(conn, %{id: "cus_123", deleted: true})
      ...> end)
      iex> response = PinStripe.Client.delete!("cus_123")
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

  @doc """
  Parses a Stripe ID or URL path into a full API path.

  Recognizes Stripe ID prefixes and converts them to the appropriate API endpoint.
  Custom paths are returned as-is.

  ## Examples

      iex> PinStripe.Client.parse_url("cus_123")
      "/customers/cus_123"

      iex> PinStripe.Client.parse_url("product_abc")
      "/products/product_abc"

      iex> PinStripe.Client.parse_url("/custom/path")
      "/custom/path"
  """
  def parse_url("product_" <> _ = id), do: "/products/#{id}"
  def parse_url("price_" <> _ = id), do: "/prices/#{id}"
  def parse_url("sub_" <> _ = id), do: "/subscriptions/#{id}"
  def parse_url("cus_" <> _ = id), do: "/customers/#{id}"
  def parse_url("cs_" <> _ = id), do: "/checkout/sessions/#{id}"
  def parse_url("inv_" <> _ = id), do: "/invoices/#{id}"
  def parse_url("evt_" <> _ = id), do: "/events/#{id}"
  def parse_url(url) when is_binary(url), do: url

  @doc """
  Converts an entity atom to its API path.

  Returns `{:ok, path}` for recognized entities, or `{:error, :unrecognized_entity_type}` otherwise.

  ## Examples

      iex> PinStripe.Client.entity_to_path(:customers)
      {:ok, "/customers"}

      iex> PinStripe.Client.entity_to_path(:products)
      {:ok, "/products"}

      iex> PinStripe.Client.entity_to_path(:invalid)
      {:error, :unrecognized_entity_type}
  """
  def entity_to_path(:customers), do: {:ok, "/customers"}
  def entity_to_path(:products), do: {:ok, "/products"}
  def entity_to_path(:prices), do: {:ok, "/prices"}
  def entity_to_path(:subscriptions), do: {:ok, "/subscriptions"}
  def entity_to_path(:invoices), do: {:ok, "/invoices"}
  def entity_to_path(:events), do: {:ok, "/events"}
  def entity_to_path(:checkout_sessions), do: {:ok, "/checkout/sessions"}
  def entity_to_path(_), do: {:error, :unrecognized_entity_type}

  @doc false
  # Encodes nested parameters into URL-encoded form data using bracket notation.
  #
  # The Stripe API expects nested parameters in bracket notation:
  #   %{metadata: %{key: "value"}} -> "metadata[key]=value"
  #   %{recurring: %{interval: "month"}} -> "recurring[interval]=month"
  #
  # This function flattens nested maps and then encodes them using URI.encode_query/1.
  defp encode_nested_params(params) when is_map(params) do
    params
    |> flatten_params()
    |> URI.encode_query()
  end

  # Recursively flattens nested maps and lists into bracket notation keys.
  #
  # Examples:
  #   %{email: "test@example.com", metadata: %{key: "value"}}
  #   -> %{"email" => "test@example.com", "metadata[key]" => "value"}
  #
  #   %{items: [%{price: "price_123"}]}
  #   -> %{"items[0][price]" => "price_123"}
  defp flatten_params(params, prefix \\ nil) do
    Enum.reduce(params, %{}, fn {key, value}, acc ->
      string_key = to_string(key)
      full_key = if prefix, do: "#{prefix}[#{string_key}]", else: string_key

      case value do
        value when is_list(value) ->
          Map.merge(acc, flatten_list(value, full_key))

        value when is_map(value) ->
          Map.merge(acc, flatten_params(value, full_key))

        value ->
          Map.put(acc, full_key, value)
      end
    end)
  end

  # Flattens lists into indexed bracket notation.
  defp flatten_list(list, prefix) do
    list
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {value, index}, acc ->
      indexed_key = "#{prefix}[#{index}]"

      case value do
        value when is_map(value) ->
          Map.merge(acc, flatten_params(value, indexed_key))

        value when is_list(value) ->
          Map.merge(acc, flatten_list(value, indexed_key))

        value ->
          Map.put(acc, indexed_key, value)
      end
    end)
  end
end
