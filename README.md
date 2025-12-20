# PinStripe

**A minimalist Stripe integration for Elixir.**

> #### Warning {: .warning}
>
> This library is still experimental! It's thoroughly tested in ExUnit, but that's it.

Stripe doesn't provide an official Elixir SDK, and maintaining a full-featured SDK has proven to be a challenge. As I see it, this is because the Elixir community is pretty senior-driven. People have no problem rolling their own integration with the incredible [Req](https://hexdocs.pm/req/Req.html) library. 

This library is an attempt to wrap those community learnings in an easy-to-use package modeled after patterns set forth in Dashbit's [SDKs with Req: Stripe](https://dashbit.co/blog/sdks-with-req-stripe) article by Wojtek Mach. 

My hope is that this should suffice for 95% of all apps that need to integrate with Stripe, and that the remaining 5% of use cases have a built-in escape hatch with Req. 

## Features

- **Simple API Client** built on Req with automatic ID prefix recognition
- **Webhook Handler DSL** using Spark for clean, declarative webhook handling
- **Automatic Signature Verification** for webhook security
- **Code Generators** powered by Igniter for zero-config setup
- **Sync with Stripe** to keep your local handlers in sync with your Stripe dashboard

## Installation

### Using Igniter (Recommended)

The fastest way to install is using the Igniter installer:

```bash
mix igniter.install pin_stripe
```

This will:
1. Add the dependency to your `mix.exs`
2. Replace `Plug.Parsers` with `PinStripe.ParsersWithRawBody` in your Phoenix endpoint (required for webhook signature verification)
3. Generate a `StripeWebhookController` in your Phoenix app with example event handlers
4. Add the webhook route to your router (default: `/webhooks/stripe`)
5. Configure `.formatter.exs` for DSL formatting support

Then configure your Stripe credentials in `config/runtime.exs`:

```elixir
config :pin_stripe,
  stripe_api_key: System.get_env("YOUR_STRIPE_KEY_ENV_VAR"),
  stripe_webhook_secret: System.get_env("YOUR_WEBHOOK_SECRET_ENV_VAR")
```

### Manual Installation

If you prefer not to use Igniter, add to your `mix.exs`:

```elixir
def deps do
  [
    {:pin_stripe, "~> 0.2"}
  ]
end
```

Then follow the [Manual Setup](#manual-setup) instructions below.

### Changing the Webhook Path

The default webhook path is `/webhooks/stripe`. If you need to change it later:

```bash
mix pin_stripe.set_webhook_path /new/webhook/path
```

### Manual Installation (without Igniter)

If you prefer not to use Igniter, you'll need to manually:

1. **Replace Plug.Parsers in your endpoint** (`lib/my_app_web/endpoint.ex`):

```elixir
# Replace this:
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  json_decoder: Jason

# With this:
plug PinStripe.ParsersWithRawBody,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  json_decoder: Jason
```

2. **Create a webhook controller** (`lib/my_app_web/stripe_webhook_controller.ex`):

```elixir
defmodule MyAppWeb.StripeWebhookController do
  use PinStripe.WebhookController

  # Define your handlers here (see examples below)
end
```

3. **Add the route** to your router (`lib/my_app_web/router.ex`):

```elixir
scope "/webhooks" do
  post "/stripe", MyAppWeb.StripeWebhookController, :create
end
```

4. **Add formatter config** to `.formatter.exs`:

```elixir
[
  import_deps: [:pin_stripe],
  # ... rest of config
]
```

## Handling Stripe Webhooks

PinStripe provides a clean DSL for handling webhook events. When Stripe sends a webhook to your endpoint, the controller automatically:
- Verifies the webhook signature using your signing secret
- Parses the event
- Dispatches it to the appropriate handler

### Function Handlers

Define inline handlers for simple event processing directly in your controller:

```elixir
defmodule MyAppWeb.StripeWebhookController do
  use PinStripe.WebhookController

  handle "customer.created", fn event ->
    customer_id = event["data"]["object"]["id"]
    email = event["data"]["object"]["email"]
    
    # Your business logic here
    MyApp.Customers.create_from_stripe(customer_id, email)
    
    :ok
  end

  handle "customer.updated", fn event ->
    # Handle customer updates
    :ok
  end

  handle "invoice.payment_succeeded", fn event ->
    # Handle successful payments
    :ok
  end
end
```

### Module Handlers

For more complex event processing, use separate handler modules:

```elixir
defmodule MyAppWeb.StripeWebhookController do
  use PinStripe.WebhookController

  handle "customer.subscription.created", MyApp.StripeWebhookHandlers.SubscriptionCreated
  handle "customer.subscription.updated", MyApp.StripeWebhookHandlers.SubscriptionUpdated
  handle "customer.subscription.deleted", MyApp.StripeWebhookHandlers.SubscriptionDeleted
end
```

```elixir
defmodule MyApp.StripeWebhookHandlers.SubscriptionCreated do
  @moduledoc """
  Handles subscription creation events.
  """

  def handle_event(event) do
    subscription = event["data"]["object"]
    customer_id = subscription["customer"]
    
    # Complex business logic
    with {:ok, user} <- MyApp.Users.find_by_stripe_customer(customer_id),
         {:ok, _subscription} <- MyApp.Subscriptions.create(user, subscription) do
      :ok
    else
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### Generating Handlers

Use the generator to quickly scaffold handlers:

```bash
# Generates a function handler
mix pin_stripe.gen.handler customer.created

# Generates a module handler
mix pin_stripe.gen.handler customer.subscription.created --handler-type module

# Generates with custom module name
mix pin_stripe.gen.handler charge.succeeded --handler-type module --module MyApp.Payments.ChargeHandler
```

The generator will:
- Validate the event name against supported Stripe events
- Add the handler to your `WebhookController`
- Generate a separate module file for module handlers

### Syncing with Stripe

Keep your local handlers in sync with your Stripe webhook configuration:

```bash
mix pin_stripe.sync_webhook_handlers
```

This task will:
1. Fetch all webhook endpoints from your Stripe account
2. Extract all enabled events
3. Compare them with your existing handlers
4. Generate stub handlers for any missing events

Options:
- `--handler-type function|module|ask` - Choose handler type for all missing events
- `--skip-confirmation` or `-y` - Skip prompts and generate all handlers
- `--api-key` or `-k` - Specify Stripe API key (otherwise uses config or prompts)

Example output:

```
Fetching webhook endpoints from Stripe...

Found 1 webhook endpoint(s):
  • https://myapp.com/webhooks/stripe (5 events)

Collecting all enabled events...

Events configured in Stripe:
  ✓ customer.created (handler exists)
  ✗ customer.updated (missing)
  ✗ invoice.payment_succeeded (missing)
  ✓ subscription.created (handler exists)
  ✗ subscription.deleted (missing)

Found 3 missing handler(s) out of 5 total Stripe event(s).

Generate handlers for missing events? (y/n) y

What type of handlers would you like to generate?
1. function
2. module
3. ask
> 1

Generating handlers...
  • customer.updated (function handler)
  • invoice.payment_succeeded (function handler)
  • subscription.deleted (function handler)

✓ Done! Generated 3 new handler(s).
```

## Calling the Stripe API

The `PinStripe.Client` module provides a simple CRUD interface for interacting with the Stripe API, built on Req.

### Basic Usage

```elixir
alias PinStripe.Client

# Fetch a customer by ID
{:ok, response} = Client.read("cus_123")
customer = response.body

# List customers with pagination
{:ok, response} = Client.read(:customers, limit: 10, starting_after: "cus_123")
customers = response.body["data"]

# Create a customer
{:ok, response} = Client.create(:customers, %{
  email: "customer@example.com",
  name: "Jane Doe",
  metadata: %{user_id: "12345"}
})

# Update a customer
{:ok, response} = Client.update("cus_123", %{
  name: "Jane Smith",
  metadata: %{premium: true}
})

# Delete a customer
{:ok, response} = Client.delete("cus_123")
```

### Automatic ID Recognition

The client automatically recognizes Stripe ID prefixes:

```elixir
Client.read("cus_123")      # => /customers/cus_123
Client.read("sub_456")      # => /subscriptions/sub_456
Client.read("price_789")    # => /prices/price_789
Client.read("product_abc")  # => /products/product_abc
Client.read("inv_xyz")      # => /invoices/inv_xyz
Client.read("evt_123")      # => /events/evt_123
Client.read("cs_test_abc")  # => /checkout/sessions/cs_test_abc
```

### Supported Entity Types

Use atoms for entity types when creating or listing:

```elixir
Client.create(:customers, %{email: "test@example.com"})
Client.create(:subscriptions, %{customer: "cus_123", items: [%{price: "price_abc"}]})
Client.create(:products, %{name: "Premium Plan"})
Client.create(:prices, %{product: "prod_123", unit_amount: 1000, currency: "usd"})
Client.create(:checkout_sessions, %{mode: "payment", line_items: [...]})

Client.read(:customers, limit: 100)
Client.read(:subscriptions, customer: "cus_123")
Client.read(:invoices, status: "paid")
```

### Bang Functions

Use `!` versions to raise on errors:

```elixir
# Raises RuntimeError on failure
response = Client.read!("cus_123")
customer = Client.create!(:customers, %{email: "test@example.com"})
```

### Advanced Usage with Req

Since the client is built on Req, you can access the full Req API:

```elixir
# Direct Req request with custom options
{:ok, response} = Client.request("/charges/ch_123", retry: :transient)

# Or build a custom client
client = Client.new(receive_timeout: 30_000)
{:ok, response} = Req.get(client, url: "/customers/cus_123")
```

## Testing

PinStripe provides comprehensive testing utilities to help you test your Stripe integrations without making real API calls.

### Mock Helpers (Recommended)

The `PinStripe.Test.Mock` module provides high-level helpers for stubbing Stripe API responses with minimal boilerplate.

#### Setup

Configure your test environment:

```elixir
# config/test.exs
config :pin_stripe,
  req_options: [plug: {Req.Test, PinStripe}]
```

#### CRUD Helpers

The easiest way to stub Stripe operations is with high-level helpers that automatically handle URL resolution and HTTP method matching:

```elixir
alias PinStripe.Test.Mock
alias PinStripe.Client

test "reads a customer" do
  Mock.stub_read("cus_123", %{
    "id" => "cus_123",
    "email" => "test@example.com"
  })
  
  {:ok, response} = Client.read("cus_123")
  assert response.body["email"] == "test@example.com"
end

test "lists customers" do
  Mock.stub_read(:customers, %{
    "object" => "list",
    "data" => [
      %{"id" => "cus_1", "email" => "user1@example.com"},
      %{"id" => "cus_2", "email" => "user2@example.com"}
    ],
    "has_more" => false
  })
  
  {:ok, response} = Client.read(:customers)
  assert length(response.body["data"]) == 2
end

test "creates a product" do
  Mock.stub_create(:products, %{
    "id" => "prod_new",
    "name" => "Test Product"
  })
  
  {:ok, response} = Client.create(:products, %{name: "Test Product"})
  assert response.body["id"] == "prod_new"
end

test "updates a customer" do
  Mock.stub_update("cus_123", %{
    "id" => "cus_123",
    "name" => "Updated Name"
  })
  
  {:ok, response} = Client.update("cus_123", %{name: "Updated Name"})
  assert response.body["name"] == "Updated Name"
end

test "deletes a customer" do
  Mock.stub_delete("cus_123", %{
    "id" => "cus_123",
    "deleted" => true,
    "object" => "customer"
  })
  
  {:ok, response} = Client.delete("cus_123")
  assert response.body["deleted"] == true
end

test "handles not found error" do
  Mock.stub_error("cus_nonexistent", 404, %{
    "error" => %{
      "type" => "invalid_request_error",
      "code" => "resource_missing"
    }
  })
  
  assert {:error, %{status: 404}} = Client.read("cus_nonexistent")
end

test "handles validation error on create" do
  Mock.stub_error(:customers, 400, %{
    "error" => %{
      "message" => "Invalid email address",
      "param" => "email"
    }
  })
  
  {:error, response} = Client.create(:customers, %{email: "invalid"})
  assert response.body["error"]["param"] == "email"
end

test "handles API key error for any request" do
  Mock.stub_error(:any, 401, %{
    "error" => %{"message" => "Invalid API key"}
  })
  
  assert {:error, %{status: 401}} = Client.read("cus_123")
end
```

**Available helpers:**
- `stub_read/2` - Stub read operations (by ID or entity type for lists)
- `stub_create/2` - Stub create operations (by entity type)
- `stub_update/2` - Stub update operations (by ID)
- `stub_delete/2` - Stub delete operations (by ID)
- `stub_error/3` - Stub error responses (for ID, entity type, or `:any`)

These helpers work seamlessly with fixtures:

```elixir
test "uses fixture with helper" do
  customer = PinStripe.Test.Fixtures.load(:customer)
  Mock.stub_read("cus_123", customer)
  
  {:ok, response} = Client.read("cus_123")
  assert response.body["object"] == "customer"
end

test "uses error fixture with helper" do
  error = PinStripe.Test.Fixtures.load(:error_404)
  Mock.stub_error("cus_missing", 404, error)
  
  assert {:error, %{status: 404}} = Client.read("cus_missing")
end
```

#### Advanced Stubbing

For more complex scenarios like handling multiple operations in one stub, use the lower-level `stub/1` function:

```elixir
test "handles multiple operations in one stub" do
  Mock.stub(fn conn ->
    case {conn.method, conn.request_path} do
      {"GET", "/v1/customers/" <> id} ->
        Mock.json(conn, %{"id" => id, "email" => "#{id}@example.com"})
      
      {"POST", "/v1/customers"} ->
        Mock.json(conn, %{"id" => "cus_new", "email" => "new@example.com"})
      
      {"DELETE", "/v1/customers/" <> id} ->
        Mock.json(conn, %{"id" => id, "deleted" => true})
      
      _ ->
        conn
    end
  end)
  
  {:ok, read_resp} = Client.read("cus_123")
  {:ok, create_resp} = Client.create(:customers, %{email: "new@example.com"})
  {:ok, delete_resp} = Client.delete("cus_123")
end
```

For more details, see the [PinStripe.Test.Mock](https://hexdocs.pm/pin_stripe/PinStripe.Test.Mock.html) documentation.

### Fixtures (Advanced)

For tests that need realistic Stripe API responses, `PinStripe.Test.Fixtures` provides automatic fixture generation from real Stripe data.

#### Fixture Types

**Error Fixtures (Atoms)** - Self-contained, instant generation:
- Use atoms: `:error_400`, `:error_401`, `:error_402`, etc.
- No Stripe CLI required
- No API calls made
- Not cached to filesystem
- Match actual Stripe error responses

**API Resources & Webhooks (Strings)** - Require Stripe setup:
- Use strings: `"customer"`, `"invoice"`, `"customer.created"`, etc.
- Require Stripe CLI and test mode API key
- Created via real Stripe API
- Cached to filesystem after first generation

#### ⚠️  Important: Side Effects (API Resources Only)

**API resource fixture generation creates real test data in your Stripe account.**

- Resources (customers, products, etc.) are created in test mode
- Objects are marked with "PinStripe Test Fixture" for identification
- Only test mode API keys (starting with `sk_test_`) are allowed
- **Recommendation:** Commit generated fixtures to git so they only generate once

Error fixtures are self-contained and don't create any side effects.

#### Requirements (API Resources Only)

- [Stripe CLI](https://stripe.com/docs/stripe-cli) installed and authenticated
- Test mode API key configured

#### Setup

Configure your test mode API key:

```elixir
# config/test.exs
config :pin_stripe,
  stripe_api_key: System.get_env("STRIPE_SECRET_KEY"),
  req_options: [plug: {Req.Test, PinStripe}]
```

#### Basic Usage

**Error fixtures (atoms)** - instant, no setup required:

```elixir
test "handles not found error" do
  # Error fixtures use atoms and generate instantly
  error = PinStripe.Test.Fixtures.load(:error_404)
  
  Req.Test.stub(PinStripe, fn conn ->
    conn
    |> Plug.Conn.put_status(404)
    |> Req.Test.json(error)
  end)
  
  assert {:error, %{status: 404}} = Client.read("cus_nonexistent")
  assert error["error"]["code"] == "resource_missing"
end
```

**API resource fixtures (strings)** - require Stripe CLI:

```elixir
test "creates a customer" do
  # Load/generate a customer fixture (auto-cached)
  # Requires Stripe CLI on first run
  fixture = PinStripe.Test.Fixtures.load(:customer)
  
  Req.Test.stub(PinStripe, fn conn ->
    Req.Test.json(conn, fixture)
  end)
  
  {:ok, response} = Client.create(:customers, %{email: "test@example.com"})
  assert response.body["object"] == "customer"
end
```

On first run (API resources only):
1. Validates your test mode API key
2. Detects your Stripe account's API version
3. Creates a customer in Stripe test mode
4. Caches the response in `test/fixtures/stripe/customer.json`
5. Returns the fixture data

Subsequent test runs use the cached fixture (no API calls).

#### Customizing Fixtures

Generate fixtures with specific attributes:

```elixir
# Customer with specific email (use atoms for API resources)
customer = PinStripe.Test.Fixtures.load(:customer, email: "alice@test.com")

# Customer with metadata
customer = PinStripe.Test.Fixtures.load(:customer,
  email: "test@example.com",
  metadata: %{user_id: "123", plan: "premium"}
)

# Webhook event with custom data (use strings for webhook events - they have dots)
event = PinStripe.Test.Fixtures.load("customer.created",
  data: %{object: %{email: "custom@test.com"}}
)
```

Each unique combination of options creates a separate cached fixture:

```
test/fixtures/stripe/
  .api_version              # Tracks current API version
  customer.json             # Base customer fixture
  customer-a3f2b9c1.json   # Customer with email: "alice@test.com"
  customer-d8e4f7a2.json   # Customer with different options
```

#### API Version Management

Fixtures match your Stripe account's API version at the time they're first generated. The version is tracked in `test/fixtures/stripe/.api_version`.

When you upgrade your Stripe account's API version, run:

```bash
mix pin_stripe.sync_api_version
```

This will:
- Detect your account's current API version
- Clear all existing fixtures if the version changed
- Update the `.api_version` file
- Fixtures will regenerate with the new version on next test run

#### Supported Fixtures

**API Resources:**
- `customer`, `product`, `price`, `subscription`, `invoice`
- `charge`, `payment_intent`, `refund`

**Webhook Events:**
- `customer.created`, `customer.updated`, `customer.deleted`
- `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`
- `invoice.paid`, `invoice.payment_failed`

**Error Responses:**
- `error_404`, `error_400`, `error_401`, `error_429`

#### Testing Examples

**Testing API responses:**

```elixir
test "handles customer creation" do
  fixture = PinStripe.Test.Fixtures.load(:customer)
  
  Req.Test.stub(PinStripe, fn conn ->
    Req.Test.json(conn, fixture)
  end)
  
  {:ok, response} = Client.create(:customers, %{email: "test@example.com"})
  assert response.body["id"] == fixture["id"]
end
```

**Testing webhook handlers:**

```elixir
test "handles customer.created webhook" do
  event = PinStripe.Test.Fixtures.load("customer.created")
  
  conn = build_webhook_conn(event)
  conn = MyAppWeb.StripeWebhookController.create(conn, event)
  
  assert conn.status == 200
end
```

**Testing error handling:**

```elixir
test "handles not found error" do
  error = PinStripe.Test.Fixtures.load("error_404")
  
  Req.Test.stub(PinStripe, fn conn ->
    conn
    |> Plug.Conn.put_status(404)
    |> Req.Test.json(error)
  end)
  
  assert {:error, %{status: 404}} = Client.read("cus_nonexistent")
end
```

**Testing with multiple variations:**

```elixir
test "handles different customer types" do
  free_user = PinStripe.Test.Fixtures.load(:customer, 
    metadata: %{plan: "free"}
  )
  premium_user = PinStripe.Test.Fixtures.load(:customer,
    metadata: %{plan: "premium"}
  )
  
  # Each gets cached separately and can be used in tests
  assert free_user["metadata"]["plan"] == "free"
  assert premium_user["metadata"]["plan"] == "premium"
end
```

#### Best Practices

**1. Commit fixtures to git**

To avoid regenerating fixtures on every machine:

```bash
git add test/fixtures/stripe
git commit -m "Add Stripe test fixtures"
```

**2. Use base fixtures and modify**

Instead of generating many custom fixtures:

```elixir
# Load base fixture
customer = PinStripe.Test.Fixtures.load(:customer)

# Modify as needed in your test
customer = Map.put(customer, "email", "specific@test.com")
```

**3. Clean up test data periodically**

Objects accumulate in your Stripe test account. They're marked with metadata for easy identification:

```bash
# List PinStripe test objects
stripe customers list --limit 100 | grep "PinStripe Test Fixture"

# Delete a specific customer
stripe customers delete cus_xxx
```

For full documentation, see [PinStripe.Test.Fixtures](https://hexdocs.pm/pin_stripe/PinStripe.Test.Fixtures.html).

## Configuration

```elixir
# config/config.exs
config :pin_stripe,
  stripe_api_key: System.get_env("STRIPE_SECRET_KEY"),
  stripe_webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET")

# config/test.exs  
config :pin_stripe,
  req_options: [plug: {Req.Test, PinStripe}]
```

****

## Special Thanks
 * [Stripity Stripe](https://github.com/beam-community/stripity-stripe)
 * Wojtek Mach
 * Dashbit
 * Zach Daniel and the Ash Team
 * All contributors to [this discussion](https://elixirforum.com/t/is-stripity-stripe-maintained)