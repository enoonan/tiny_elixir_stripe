defmodule PinStripe.Test.Fixtures do
  @moduledoc """
  Automatically generates and caches Stripe API fixtures for testing.

  Fixtures are generated using your Stripe account's API version via the Stripe CLI
  and cached in `test/fixtures/stripe/`. The API version is tracked in `.api_version`.

  ## ⚠️  Important: Side Effects

  **Fixture generation creates real test data in your Stripe account.**

  - Resources (customers, products, etc.) are created in test mode
  - Objects are marked with "PinStripe Test Fixture" for identification
  - Only test mode API keys (starting with `sk_test_`) are allowed
  - Consider committing fixtures to git to avoid regenerating

  ## Requirements

  - Stripe CLI installed: `brew install stripe/stripe-cli/stripe`
  - Stripe CLI authenticated: `stripe login`
  - Test mode API key configured (starts with `sk_test_`)

  ## Quick Start

  ### Configuration

      # config/test.exs
      config :pin_stripe,
        stripe_api_key: System.get_env("STRIPE_SECRET_KEY")

  ### Basic Usage

      # In your test
      test "creates a customer" do
        # Load/generate a customer fixture (use atoms for API resources)
        customer = PinStripe.Test.Fixtures.load(:customer)
        
        # Use with Req.Test
        Req.Test.stub(PinStripe, fn conn ->
          Req.Test.json(conn, customer)
        end)
        
        {:ok, response} = Client.create(:customers, %{email: "test@example.com"})
        assert response.body["object"] == "customer"
      end

  ## Customizing Fixtures

  Generate fixtures with specific attributes by passing options:

      # Customer with specific email (atoms for API resources)
      customer = PinStripe.Test.Fixtures.load(:customer,
        email: "alice@example.com",
        name: "Alice Smith"
      )

      # Customer with metadata
      customer = PinStripe.Test.Fixtures.load(:customer,
        metadata: %{user_id: "123", plan: "premium"}
      )

      # Webhook event with custom data (strings for webhook events - they have dots)
      event = PinStripe.Test.Fixtures.load("customer.created",
        data: %{object: %{email: "custom@example.com"}}
      )

  Each unique set of options creates a separate cached fixture file.
  The filename includes a hash of the options for uniqueness:

      test/fixtures/stripe/
        customer.json              # Base customer
        customer-a3f2b9c1.json    # Customized customer

  ## API Version Management

  Fixtures match your Stripe account's default API version at the time they're
  first generated. The version is stored in `test/fixtures/stripe/.api_version`.

  When you upgrade your Stripe account's API version, run the sync task to clear
  old fixtures and regenerate them with the new version:

      mix pin_stripe.sync_api_version

  This task:
  - Detects your account's current API version
  - Compares it with the cached version
  - Clears all fixtures if the version changed
  - Updates the `.api_version` file

  ## Supported Fixtures

  ### API Resources (Atoms)
  - `:customer` - Customer objects
  - `:product` - Product objects
  - `:price` - Price objects
  - `:subscription` - Subscription objects
  - `:invoice` - Invoice objects
  - `:charge` - Charge objects (one-time payments)
  - `:payment_intent` - PaymentIntent objects (modern payment flow)
  - `:refund` - Refund objects

  ### Webhook Events (Strings - they have dots)
  - `"customer.created"`, `"customer.updated"`, `"customer.deleted"`
  - `"customer.subscription.created"`, `"customer.subscription.updated"`, `"customer.subscription.deleted"`
  - `"invoice.paid"`, `"invoice.payment_failed"`

  ### Error Responses (Atoms)
  - `:error_404` - Not found (resource_missing)
  - `:error_400` - Bad request (invalid_request_error)
  - `:error_401` - Unauthorized (authentication error)
  - `error_429` - Rate limit exceeded

  ## Testing Best Practices

  ### Commit Fixtures to Git

  To avoid generating fixtures in CI or on every developer machine:

      # Commit fixtures to version control
      git add test/fixtures/stripe
      git commit -m "Add Stripe test fixtures"

  ### Use Base Fixtures and Modify

  Instead of generating many custom fixtures:

      # Load base fixture
      customer = PinStripe.Test.Fixtures.load(:customer)

      # Modify as needed in your test
      customer = Map.put(customer, "email", "specific@test.com")

  ### Clean Up Test Data

  Objects created during fixture generation accumulate in your Stripe test account.
  They're marked with `pinstripe_fixture: true` metadata for easy identification.

  To clean up manually:

      # List PinStripe test objects
      stripe customers list --limit 100 | grep "PinStripe Test Fixture"

      # Delete a specific customer
      stripe customers delete cus_xxx

  ## Examples

  ### Testing API Responses

      test "handles customer creation" do
        fixture = PinStripe.Test.Fixtures.load(:customer)
        
        Req.Test.stub(PinStripe, fn conn ->
          Req.Test.json(conn, fixture)
        end)
        
        {:ok, response} = Client.create(:customers, %{email: "test@example.com"})
        assert response.body["id"] == fixture["id"]
      end

  ### Testing Webhook Handlers

      test "handles customer.created webhook" do
        event = PinStripe.Test.Fixtures.load("customer.created")
        
        conn = build_webhook_conn(event)
        conn = MyAppWeb.StripeWebhookController.create(conn, event)
        
        assert conn.status == 200
      end

  ### Testing Error Handling

      test "handles not found error" do
        error = PinStripe.Test.Fixtures.load(:error_404)
        
        Req.Test.stub(PinStripe, fn conn ->
          conn
          |> Plug.Conn.put_status(404)
          |> Req.Test.json(error)
        end)
        
        assert {:error, %{status: 404}} = Client.read("cus_nonexistent")
      end

  ### Testing with Multiple Customers

      test "handles multiple customers" do
        alice = PinStripe.Test.Fixtures.load(:customer, email: "alice@test.com")
        bob = PinStripe.Test.Fixtures.load(:customer, email: "bob@test.com")
        
        # Each gets cached separately
        assert alice["email"] == "alice@test.com"
        assert bob["email"] == "bob@test.com"
      end
  """

  require Logger

  @default_fixtures_dir "test/fixtures/stripe"
  @api_version_file ".api_version"

  @doc """
  Loads a fixture by name, generating it if not cached.

  ## Fixture Types

  **Error Fixtures (Atoms)** - Self-contained, no Stripe CLI required:
  - Use atoms: `:error_400`, `:error_401`, `:error_402`, `:error_403`, `:error_404`, 
    `:error_409`, `:error_424`, `:error_429`, `:error_500`, `:error_502`, 
    `:error_503`, `:error_504`
  - Generated instantly (no API calls)
  - Match actual Stripe error responses
  - Not cached to filesystem

  **API Resources (Atoms)** - Require Stripe CLI and API key:
  - Use atoms: `:customer`, `:product`, `:price`, `:subscription`, 
    `:invoice`, `:charge`, `:payment_intent`, `:refund`
  - Created via Stripe API
  - Cached to filesystem
  - Options passed to Stripe CLI during creation

  **Webhook Events (Strings)** - Require Stripe CLI and API key:
  - Use strings with dots: `"customer.created"`, `"invoice.paid"`, etc.
  - Generated via Stripe CLI trigger
  - Cached to filesystem
  - Options used to modify event data after generation

  ## Options

  Options are used to customize fixtures. Each unique combination of options 
  creates a separate cached fixture (for API resources/webhooks only).

  ## Examples

  Error fixtures use atoms and are self-contained:

      iex> error = PinStripe.Test.Fixtures.load(:error_404)
      iex> error["error"]["type"]
      "invalid_request_error"
      iex> error["error"]["code"]
      "resource_missing"

      iex> error = PinStripe.Test.Fixtures.load(:error_400)
      iex> error["error"]["type"]
      "invalid_request_error"
      iex> error["error"]["code"]
      "parameter_invalid_empty"

      iex> error = PinStripe.Test.Fixtures.load(:error_401)
      iex> error["error"]["type"]
      "invalid_request_error"

      iex> error = PinStripe.Test.Fixtures.load(:error_429)
      iex> error["error"]["type"]
      "rate_limit_error"

  API resources use atoms and webhook events use strings (both require Stripe CLI):

      # API resources use atoms - require real Stripe setup
      PinStripe.Test.Fixtures.load(:customer)
      #=> %{"id" => "cus_...", "object" => "customer", ...}
      
      PinStripe.Test.Fixtures.load(:customer, email: "test@example.com")
      #=> %{"id" => "cus_...", "email" => "test@example.com", ...}
      
      # Webhook events use strings (they have dots)
      PinStripe.Test.Fixtures.load("customer.created")
      #=> %{"id" => "evt_...", "type" => "customer.created", ...}
  """
  def load(fixture_name, opts \\ [])

  # Error fixtures (atoms) - generate instantly, no caching
  def load(fixture_name, opts) when is_atom(fixture_name) do
    case fixture_name do
      name
      when name in [
             :error_400,
             :error_401,
             :error_402,
             :error_403,
             :error_404,
             :error_409,
             :error_424,
             :error_429,
             :error_500,
             :error_502,
             :error_503,
             :error_504
           ] ->
        # Error fixtures don't need caching or API initialization
        generate_fixture(fixture_name, opts)

      # API resource atoms
      name
      when name in [
             :customer,
             :product,
             :price,
             :subscription,
             :invoice,
             :charge,
             :payment_intent,
             :refund
           ] ->
        ensure_api_version_initialized!()

        # Use atom name for filename
        filename = fixture_filename(Atom.to_string(fixture_name), opts)
        fixture_path = Path.join(fixtures_dir(), filename)

        # Try to load from cache
        case File.read(fixture_path) do
          {:ok, content} ->
            Jason.decode!(content)

          {:error, :enoent} ->
            # Generate and cache
            File.mkdir_p!(fixtures_dir())
            fixture_data = generate_fixture(fixture_name, opts)
            json = Jason.encode!(fixture_data, pretty: true)
            File.write!(fixture_path, json)
            fixture_data
        end

      _ ->
        raise "Unknown atom fixture: #{inspect(fixture_name)}"
    end
  end

  # Webhook event fixtures (strings with dots) - use filesystem caching
  def load(fixture_name, opts) when is_binary(fixture_name) do
    # Validate that this is a valid webhook event
    unless valid_webhook_event?(fixture_name) do
      raise """
      Unknown fixture: #{fixture_name}

      Supported fixtures:
        API Resources (atoms): :customer, :product, :price, :subscription, :invoice, :charge, :payment_intent, :refund
        Webhook Events (strings): "customer.created", "invoice.paid", etc. (see priv/supported_stripe_events.txt)
        Errors (atoms): :error_400, :error_401, :error_402, :error_403, :error_404, :error_409, :error_424, :error_429, :error_500, :error_502, :error_503, :error_504
      """
    end

    ensure_api_version_initialized!()

    # Generate filename (with hash if options provided)
    filename = fixture_filename(fixture_name, opts)
    fixture_path = Path.join(fixtures_dir(), filename)

    # Try to load from cache
    case File.read(fixture_path) do
      {:ok, content} ->
        Jason.decode!(content)

      {:error, :enoent} ->
        # Generate and cache
        generate_and_cache(fixture_name, fixture_path, opts)
    end
  end

  @doc """
  Lists all available (cached) fixtures.

  Returns a list of fixture filenames (without .json extension), sorted alphabetically.
  Returns an empty list if no fixtures directory exists.

  ## Examples

      iex> # When no fixtures exist
      iex> Application.put_env(:pin_stripe, :fixtures_dir, "test/fixtures/doctest_empty")
      iex> File.rm_rf!("test/fixtures/doctest_empty")
      iex> PinStripe.Test.Fixtures.list()
      []

      iex> # Lists cached API resource fixtures (not error fixtures which use atoms)
      iex> # Error fixtures don't create files, so list() returns only cached API resources
      iex> Application.put_env(:pin_stripe, :fixtures_dir, "test/fixtures/stripe")
      iex> list = PinStripe.Test.Fixtures.list()
      iex> "error_400" in list
      true
      iex> "error_404" in list
      true
      iex> Application.delete_env(:pin_stripe, :fixtures_dir)
      :ok
  """
  def list do
    dir = fixtures_dir()

    if File.exists?(dir) do
      File.ls!(dir)
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.map(&String.replace_suffix(&1, ".json", ""))
      |> Enum.sort()
    else
      []
    end
  end

  @doc """
  Returns the API version used for cached fixtures.

  Returns nil if no .api_version file exists yet.

  ## Examples

      iex> # When no .api_version file exists
      iex> Application.put_env(:pin_stripe, :fixtures_dir, "test/fixtures/doctest_no_version")
      iex> File.rm_rf!("test/fixtures/doctest_no_version")
      iex> PinStripe.Test.Fixtures.api_version()
      nil

      iex> # After creating a version file
      iex> Application.put_env(:pin_stripe, :fixtures_dir, "test/fixtures/doctest_version")
      iex> File.rm_rf!("test/fixtures/doctest_version")
      iex> File.mkdir_p!("test/fixtures/doctest_version")
      iex> File.write!("test/fixtures/doctest_version/.api_version", "2024-06-20")
      iex> PinStripe.Test.Fixtures.api_version()
      "2024-06-20"
      iex> File.rm_rf!("test/fixtures/doctest_version")
      iex> Application.delete_env(:pin_stripe, :fixtures_dir)
      :ok
  """
  def api_version do
    version_file = Path.join(fixtures_dir(), @api_version_file)

    case File.read(version_file) do
      {:ok, content} -> String.trim(content)
      {:error, :enoent} -> nil
    end
  end

  @doc """
  Detects the current Stripe account's API version.

  Makes a quick API call to determine the version. Requires a valid Stripe API key
  and authenticated Stripe CLI.

  ## Examples

      # Requires real Stripe setup
      PinStripe.Test.Fixtures.detect_account_api_version()
      #=> "2024-06-20"
  """
  def detect_account_api_version do
    validate_api_key!()

    case stripe_cli(["get", "/v1/customers", "--limit", "1", "--show-headers"]) do
      {:ok, output} ->
        case Regex.run(~r/< Stripe-Version: (.+)/, output) do
          [_, version] -> String.trim(version)
          _ -> raise "Could not detect API version from Stripe response"
        end

      {:error, reason} ->
        raise "Failed to detect API version: #{reason}"
    end
  end

  # Private functions

  defp fixtures_dir do
    Application.get_env(:pin_stripe, :fixtures_dir, @default_fixtures_dir)
  end

  defp ensure_api_version_initialized! do
    dir = fixtures_dir()
    version_file = Path.join(dir, @api_version_file)

    case File.read(version_file) do
      {:ok, _cached_version} ->
        # Version file exists, nothing to do
        :ok

      {:error, :enoent} ->
        # First time setup - initialize the version file
        validate_api_key!()
        current_version = detect_account_api_version()

        File.mkdir_p!(dir)
        File.write!(version_file, current_version)

        Logger.info("Initialized fixtures with API version: #{current_version}")
    end
  end

  defp validate_api_key! do
    api_key = get_api_key()

    cond do
      is_nil(api_key) ->
        raise """
        No Stripe API key configured.

        Set your test mode API key:
          # config/test.exs
          config :pin_stripe, stripe_api_key: "sk_test_..."

        Or set environment variable:
          export STRIPE_SECRET_KEY="sk_test_..."
        """

      String.starts_with?(api_key, "sk_live_") ->
        raise """
        ❌ DANGER: Live mode API key detected!

        Fixture generation creates test data in Stripe and MUST only use test mode keys.

        Your key starts with 'sk_live_' which is a LIVE MODE key.

        ⚠️  DO NOT proceed with a live key!

        Use a test mode key instead (starts with 'sk_test_').
        """

      not String.starts_with?(api_key, "sk_test_") ->
        raise """
        Invalid API key format.

        Fixture generation requires a test mode API key starting with 'sk_test_'.
        Your key starts with: #{String.slice(api_key, 0, 10)}...

        Get a test key from: https://dashboard.stripe.com/test/apikeys
        """

      true ->
        :ok
    end
  end

  defp get_api_key do
    Application.get_env(:pin_stripe, :stripe_api_key) ||
      System.get_env("STRIPE_SECRET_KEY")
  end

  defp fixture_filename(fixture_name, []), do: "#{fixture_name}.json"

  defp fixture_filename(fixture_name, opts) do
    hash = options_hash(opts)
    "#{fixture_name}-#{hash}.json"
  end

  defp options_hash(opts) when opts == [] or opts == %{}, do: nil

  defp options_hash(opts) do
    opts
    |> normalize_options()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end

  defp normalize_options(opts) do
    opts
    |> Enum.into(%{})
    |> Enum.sort()
    |> Enum.into(%{})
  end

  defp generate_and_cache(fixture_name, fixture_path, opts) do
    File.mkdir_p!(fixtures_dir())

    fixture_data = generate_fixture(fixture_name, opts)

    json = Jason.encode!(fixture_data, pretty: true)
    File.write!(fixture_path, json)

    fixture_data
  end

  defp valid_webhook_event?(event) do
    supported_events_file =
      Path.join(:code.priv_dir(:pin_stripe), "supported_stripe_events.txt")

    if File.exists?(supported_events_file) do
      supported_events =
        supported_events_file
        |> File.read!()
        |> String.split("\n", trim: true)
        |> MapSet.new()

      MapSet.member?(supported_events, event)
    else
      # If the file doesn't exist, allow any event (dev mode)
      true
    end
  end

  # Error fixtures - pattern match directly on atoms
  defp generate_fixture(:error_400, _opts) do
    %{
      "error" => %{
        "code" => "parameter_invalid_empty",
        "doc_url" => "https://stripe.com/docs/error-codes/parameter-invalid-empty",
        "message" => "Invalid request: missing required parameter",
        "type" => "invalid_request_error"
      }
    }
  end

  defp generate_fixture(:error_401, _opts) do
    %{
      "error" => %{
        "message" => "Invalid API Key provided",
        "type" => "invalid_request_error"
      }
    }
  end

  defp generate_fixture(:error_402, _opts) do
    %{
      "error" => %{
        "code" => "card_declined",
        "doc_url" => "https://stripe.com/docs/error-codes/card-declined",
        "message" => "Your card was declined",
        "type" => "card_error"
      }
    }
  end

  defp generate_fixture(:error_403, _opts) do
    %{
      "error" => %{
        "code" => "account_invalid",
        "message" => "The API key doesn't have permissions to perform the request",
        "type" => "invalid_request_error"
      }
    }
  end

  defp generate_fixture(:error_404, _opts) do
    %{
      "error" => %{
        "code" => "resource_missing",
        "doc_url" => "https://stripe.com/docs/error-codes/resource-missing",
        "message" => "No such resource",
        "type" => "invalid_request_error"
      }
    }
  end

  defp generate_fixture(:error_409, _opts) do
    %{
      "error" => %{
        "code" => "idempotency_key_in_use",
        "message" => "The idempotency key provided is currently being used in another request",
        "type" => "idempotency_error"
      }
    }
  end

  defp generate_fixture(:error_424, _opts) do
    %{
      "error" => %{
        "message" =>
          "The request couldn't be completed due to a failure in a dependency external to Stripe",
        "type" => "api_error"
      }
    }
  end

  defp generate_fixture(:error_429, _opts) do
    %{
      "error" => %{
        "code" => "rate_limit",
        "message" => "Too many requests",
        "type" => "rate_limit_error"
      }
    }
  end

  defp generate_fixture(:error_500, _opts) do
    %{
      "error" => %{
        "message" => "An error occurred with our API",
        "type" => "api_error"
      }
    }
  end

  defp generate_fixture(:error_502, _opts) do
    %{
      "error" => %{
        "message" => "An error occurred with our API",
        "type" => "api_error"
      }
    }
  end

  defp generate_fixture(:error_503, _opts) do
    %{
      "error" => %{
        "message" => "An error occurred with our API",
        "type" => "api_error"
      }
    }
  end

  defp generate_fixture(:error_504, _opts) do
    %{
      "error" => %{
        "message" => "An error occurred with our API",
        "type" => "api_error"
      }
    }
  end

  # API resource fixtures - pattern match on atoms
  defp generate_fixture(:customer, opts), do: generate_customer(opts)
  defp generate_fixture(:product, opts), do: generate_product(opts)
  defp generate_fixture(:price, opts), do: generate_price(opts)
  defp generate_fixture(:subscription, opts), do: generate_subscription(opts)
  defp generate_fixture(:invoice, opts), do: generate_invoice(opts)
  defp generate_fixture(:charge, opts), do: generate_charge(opts)
  defp generate_fixture(:payment_intent, opts), do: generate_payment_intent(opts)
  defp generate_fixture(:refund, opts), do: generate_refund(opts)

  # String-based fixtures (webhook events only - they have dots)
  defp generate_fixture(fixture_name, opts) when is_binary(fixture_name) do
    if String.contains?(fixture_name, ".") do
      generate_webhook_event(fixture_name, opts)
    else
      raise """
      Unknown fixture: #{fixture_name}

      Supported fixtures:
        API Resources (atoms): :customer, :product, :price, :subscription, :invoice, :charge, :payment_intent, :refund
        Webhook Events (strings): "customer.created", "invoice.paid", etc.
        Errors (atoms): :error_400, :error_401, :error_402, :error_403, :error_404, :error_409, :error_424, :error_429, :error_500, :error_502, :error_503, :error_504
      """
    end
  end

  # Catch-all for unknown atoms
  defp generate_fixture(fixture_name, _opts) when is_atom(fixture_name) do
    raise """
    Unknown atom fixture: #{inspect(fixture_name)}

    Supported fixtures:
      API Resources (atoms): :customer, :product, :price, :subscription, :invoice, :charge, :payment_intent, :refund
      Webhook Events (strings): "customer.created", "invoice.paid", etc.
      Errors (atoms): :error_400, :error_401, :error_402, :error_403, :error_404, :error_409, :error_424, :error_429, :error_500, :error_502, :error_503, :error_504
    """
  end

  defp generate_customer(opts) do
    Logger.info("Generating customer fixture with Stripe CLI...")
    # Build CLI arguments with metadata
    default_opts = %{
      description: "PinStripe Test Fixture",
      metadata: %{
        pinstripe_fixture: "true",
        generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    merged_opts = Map.merge(default_opts, normalize_options(opts))
    args = ["customers", "create"] ++ format_stripe_cli_options(merged_opts)

    # Create customer
    case stripe_cli(args) do
      {:ok, output} ->
        customer = Jason.decode!(output)
        customer_id = customer["id"]

        # Fetch clean response
        case stripe_cli(["get", customer_id]) do
          {:ok, output} -> Jason.decode!(output)
          {:error, reason} -> raise "Failed to fetch customer: #{reason}"
        end

      {:error, reason} ->
        raise "Failed to create customer: #{reason}"
    end
  end

  defp generate_product(opts) do
    Logger.info("Generating product fixture with Stripe CLI...")

    default_opts = %{
      name: "PinStripe Test Product",
      description: "PinStripe Test Fixture",
      metadata: %{pinstripe_fixture: "true"}
    }

    merged_opts = Map.merge(default_opts, normalize_options(opts))
    args = ["products", "create"] ++ format_stripe_cli_options(merged_opts)

    case stripe_cli(args) do
      {:ok, output} -> Jason.decode!(output)
      {:error, reason} -> raise "Failed to create product: #{reason}"
    end
  end

  defp generate_price(opts) do
    Logger.info("Generating price fixture with Stripe CLI...")

    # Price requires a product - create one if not provided
    product_id =
      case Map.get(normalize_options(opts), :product) do
        nil ->
          Logger.info("Creating product for price...")
          product = generate_product(%{name: "Test Product for Price"})
          product["id"]

        id ->
          id
      end

    # Default price options
    default_opts = %{
      product: product_id,
      unit_amount: 1000,
      currency: "usd"
    }

    merged_opts = Map.merge(default_opts, normalize_options(opts))

    args = ["prices", "create"] ++ format_stripe_cli_options(merged_opts)

    case stripe_cli(args) do
      {:ok, output} -> Jason.decode!(output)
      {:error, reason} -> raise "Failed to create price: #{reason}"
    end
  end

  defp generate_subscription(opts) do
    Logger.info("Generating subscription fixture with Stripe CLI...")

    # Subscription requires customer, product, and price
    Logger.info("Creating prerequisites for subscription...")

    customer = generate_customer(%{})
    product = generate_product(%{name: "Test Subscription Product"})

    price =
      generate_price(%{
        product: product["id"],
        unit_amount: 1000,
        currency: "usd",
        recurring: %{interval: "month"}
      })

    Logger.info("Creating subscription...")

    default_opts = %{
      customer: customer["id"],
      metadata: %{pinstripe_fixture: "true"}
    }

    # Note: items needs special handling with -d flag
    merged_opts = Map.merge(default_opts, normalize_options(opts))

    args =
      [
        "subscriptions",
        "create",
        "-d",
        "items[0][price]=#{price["id"]}"
      ] ++ format_stripe_cli_options(merged_opts)

    case stripe_cli(args) do
      {:ok, output} -> Jason.decode!(output)
      {:error, reason} -> raise "Failed to create subscription: #{reason}"
    end
  end

  defp generate_invoice(opts) do
    Logger.info("Generating invoice fixture with Stripe CLI...")

    # Invoice requires customer
    Logger.info("Creating customer for invoice...")
    customer = generate_customer(%{})

    Logger.info("Creating invoice...")

    default_opts = %{
      customer: customer["id"],
      metadata: %{pinstripe_fixture: "true"}
    }

    merged_opts = Map.merge(default_opts, normalize_options(opts))
    args = ["invoices", "create"] ++ format_stripe_cli_options(merged_opts)

    case stripe_cli(args) do
      {:ok, output} -> Jason.decode!(output)
      {:error, reason} -> raise "Failed to create invoice: #{reason}"
    end
  end

  defp generate_charge(opts) do
    Logger.info("Generating charge fixture with Stripe CLI...")

    # Charge requires a payment source - we'll use a test token

    # Default charge options with test card token
    default_opts = %{
      amount: 1000,
      currency: "usd",
      source: "tok_visa",
      description: "PinStripe Test Fixture"
    }

    merged_opts = Map.merge(default_opts, normalize_options(opts))

    args = ["charges", "create"] ++ format_stripe_cli_options(merged_opts)

    case stripe_cli(args) do
      {:ok, output} -> Jason.decode!(output)
      {:error, reason} -> raise "Failed to create charge: #{reason}"
    end
  end

  defp generate_payment_intent(opts) do
    Logger.info("Generating payment_intent fixture with Stripe CLI...")

    # Default payment intent options
    default_opts = %{
      amount: 2000,
      currency: "usd",
      metadata: %{pinstripe_fixture: "true"}
    }

    merged_opts = Map.merge(default_opts, normalize_options(opts))

    # Add payment_method_types using -d flag (arrays need special handling)
    args =
      [
        "payment_intents",
        "create",
        "-d",
        "payment_method_types[]=card"
      ] ++ format_stripe_cli_options(merged_opts)

    case stripe_cli(args) do
      {:ok, output} -> Jason.decode!(output)
      {:error, reason} -> raise "Failed to create payment_intent: #{reason}"
    end
  end

  defp generate_refund(opts) do
    Logger.info("Generating refund fixture with Stripe CLI...")

    # Refund requires a charge
    Logger.info("Creating charge for refund...")
    charge = generate_charge(%{})

    Logger.info("Creating refund...")

    default_opts = %{
      charge: charge["id"],
      metadata: %{pinstripe_fixture: "true"}
    }

    merged_opts = Map.merge(default_opts, normalize_options(opts))

    args = ["refunds", "create"] ++ format_stripe_cli_options(merged_opts)

    case stripe_cli(args) do
      {:ok, output} -> Jason.decode!(output)
      {:error, reason} -> raise "Failed to create refund: #{reason}"
    end
  end

  defp generate_webhook_event(event_type, opts) do
    Logger.info("Generating #{event_type} webhook event...")

    with {:ok, _output} <- stripe_cli(["trigger", event_type, "--skip", "post"]),
         {:ok, output} <- stripe_cli(["events", "list", "--limit", "1", "--types", event_type]) do
      response = Jason.decode!(output)
      event = List.first(response["data"])

      # Apply options via deep merge if provided
      if opts == [] do
        event
      else
        deep_merge(event, normalize_options(opts))
      end
    else
      {:error, reason} ->
        raise "Failed to generate webhook event: #{reason}"
    end
  end

  defp stripe_cli(args) do
    api_key = get_api_key()

    # Add API key if available
    cmd_args =
      if api_key do
        ["--api-key", api_key | args]
      else
        args
      end

    case System.cmd("stripe", cmd_args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, output}
    end
  rescue
    e in ErlangError ->
      if e.original == :enoent do
        {:error,
         """
         Stripe CLI not found.

         Install it:
           brew install stripe/stripe-cli/stripe

         Then authenticate:
           stripe login
         """}
      else
        {:error, "Unexpected error: #{inspect(e)}"}
      end
  end

  defp format_stripe_cli_options(opts) when opts == %{} or opts == [], do: []

  defp format_stripe_cli_options(opts) do
    opts
    |> Enum.flat_map(fn {key, value} ->
      format_cli_arg(to_string(key), value)
    end)
  end

  defp format_cli_arg("metadata", value) when is_map(value) do
    # Metadata uses -d flag with bracket notation: -d "metadata[key]=value"
    Enum.flat_map(value, fn {nested_key, nested_value} ->
      ["-d", "metadata[#{nested_key}]=#{nested_value}"]
    end)
  end

  defp format_cli_arg(key, value) when is_map(value) do
    # Handle nested maps: card: %{number: "4242..."}
    # Becomes: --card.number 4242...
    Enum.flat_map(value, fn {nested_key, nested_value} ->
      ["--#{key}.#{nested_key}", to_string(nested_value)]
    end)
  end

  defp format_cli_arg(key, value) do
    # Simple key-value: email: "test@example.com"
    # Becomes: --email test@example.com
    ["--#{key}", to_string(value)]
  end

  defp deep_merge(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override, fn _key, base_val, override_val ->
      if is_map(base_val) and is_map(override_val) do
        deep_merge(base_val, override_val)
      else
        override_val
      end
    end)
  end

  defp deep_merge(base, _override), do: base
end
