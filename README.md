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
2. Replace `Plug.Parsers` with `PinStripe.ParsersWithRawBody` in your Phoenix endpoint
3. Generate a `StripeWebhookController` with example event handlers
4. Add the webhook route to your router (default: `/webhooks/stripe`)
5. Configure `webhook_paths` in `config/runtime.exs`
6. Add DSL formatting support to `.formatter.exs`

Then configure your Stripe credentials:

```elixir
# config/runtime.exs
config :pin_stripe,
  stripe_api_key: System.get_env("STRIPE_SECRET_KEY"),
  stripe_webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET")
```

### Manual Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:pin_stripe, "~> 0.2"}
  ]
end
```

Then follow the [Manual Setup](#manual-installation-without-igniter) instructions below.

### Multiple Webhook Endpoints

To handle multiple webhook endpoints (e.g., regular and Stripe Connect):

1. **Add paths to config:**

```elixir
# config/runtime.exs
config :pin_stripe,
  webhook_paths: ["/webhooks/stripe", "/webhooks/stripe_connect"]
```

2. **Create additional controllers:**

```elixir
defmodule MyAppWeb.StripeConnectWebhookController do
  use PinStripe.WebhookController

  handle "account.updated", fn event ->
    # Handle Connect-specific events
    :ok
  end
end
```

3. **Add routes:**

```elixir
scope "/webhooks" do
  post "/stripe", MyAppWeb.StripeWebhookController, :create
  post "/stripe_connect", MyAppWeb.StripeConnectWebhookController, :create
end
```

### Manual Installation (without Igniter)

1. **Add config:**

```elixir
# config/runtime.exs
config :pin_stripe,
  stripe_api_key: System.get_env("STRIPE_SECRET_KEY"),
  stripe_webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET"),
  webhook_paths: ["/webhooks/stripe"]
```

2. **Replace Plug.Parsers in your endpoint:**

```elixir
# lib/my_app_web/endpoint.ex
plug PinStripe.ParsersWithRawBody,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  json_decoder: Jason
```

3. **Create a webhook controller:**

```elixir
# lib/my_app_web/stripe_webhook_controller.ex
defmodule MyAppWeb.StripeWebhookController do
  use PinStripe.WebhookController
end
```

4. **Add the route:**

```elixir
# lib/my_app_web/router.ex
scope "/webhooks" do
  post "/stripe", MyAppWeb.StripeWebhookController, :create
end
```

5. **Add formatter config:**

```elixir
# .formatter.exs
[
  import_deps: [:pin_stripe]
]
```

## Handling Stripe Webhooks

PinStripe provides a clean DSL for handling webhook events. Webhooks are automatically verified, parsed, and dispatched to your handlers.

### Function Handlers

For simple event processing:

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

Quickly scaffold handlers:

```bash
mix pin_stripe.gen.handler customer.created
mix pin_stripe.gen.handler customer.subscription.created --handler-type module
mix pin_stripe.gen.handler charge.succeeded --handler-type module --module MyApp.Payments.ChargeHandler
```

### Syncing with Stripe

Sync your local handlers with your Stripe webhook configuration:

```bash
mix pin_stripe.sync_webhook_handlers
```

This fetches your Stripe webhook endpoints, compares them with existing handlers, and generates stubs for missing events.

**Options:**
- `--handler-type function|module|ask`
- `--skip-confirmation` or `-y`
- `--api-key` or `-k`

**Example output:**

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

Simple CRUD interface built on Req:

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

**Automatic ID recognition:**

```elixir
Client.read("cus_123")      # => /customers/cus_123
Client.read("sub_456")      # => /subscriptions/sub_456
Client.read("price_789")    # => /prices/price_789
Client.read("product_abc")  # => /products/product_abc
Client.read("inv_xyz")      # => /invoices/inv_xyz
Client.read("evt_123")      # => /events/evt_123
Client.read("cs_test_abc")  # => /checkout/sessions/cs_test_abc
```

**Entity types:**

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

**Bang functions:**

```elixir
# Raises RuntimeError on failure
response = Client.read!("cus_123")
customer = Client.create!(:customers, %{email: "test@example.com"})
```

**Advanced usage with Req:**

```elixir
# Direct Req request with custom options
{:ok, response} = Client.request("/charges/ch_123", retry: :transient)

# Or build a custom client
client = Client.new(receive_timeout: 30_000)
{:ok, response} = Req.get(client, url: "/customers/cus_123")
```

## Testing

Test your Stripe integrations without making real API calls.

### Mock Helpers

High-level helpers for stubbing Stripe API responses:

**Setup:**

```elixir
# config/test.exs
config :pin_stripe,
  req_options: [plug: {Req.Test, PinStripe}]
```

**Examples:**

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

**Advanced stubbing:**

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

See [PinStripe.Test.Mock](https://hexdocs.pm/pin_stripe/PinStripe.Test.Mock.html) for full documentation.

### Fixtures

Generate realistic test fixtures from actual Stripe data:

**Two types:**
- **Error fixtures** (atoms like `:error_404`): Instant, no setup required
- **API resources** (atoms like `:customer`): Require Stripe CLI, created once and cached

⚠️ API resource fixtures create real test data in your Stripe account. Commit generated fixtures to git.

**Requirements for API resources:**
- [Stripe CLI](https://stripe.com/docs/stripe-cli) installed
- Test mode API key

**Setup:**

```elixir
# config/test.exs
config :pin_stripe,
  stripe_api_key: System.get_env("STRIPE_SECRET_KEY"),
  req_options: [plug: {Req.Test, PinStripe}]
```

**Usage:**

```elixir
# Error fixtures - instant
error = PinStripe.Test.Fixtures.load(:error_404)

# API resources - created once, cached
customer = PinStripe.Test.Fixtures.load(:customer)
```

**Customization:**

```elixir
customer = PinStripe.Test.Fixtures.load(:customer, email: "alice@test.com")
event = PinStripe.Test.Fixtures.load("customer.created", data: %{...})
```

**API version management:**

When you upgrade Stripe API versions:

```bash
mix pin_stripe.sync_api_version
```

**Supported fixtures:**
- API Resources: `customer`, `product`, `price`, `subscription`, `invoice`, `charge`, `payment_intent`, `refund`
- Webhook Events: `customer.created`, `customer.subscription.updated`, `invoice.paid`, etc.
- Errors: `error_404`, `error_400`, `error_401`, `error_429`

See [PinStripe.Test.Fixtures](https://hexdocs.pm/pin_stripe/PinStripe.Test.Fixtures.html) for full documentation.

## Configuration

```elixir
# config/runtime.exs
config :pin_stripe,
  stripe_api_key: System.get_env("STRIPE_SECRET_KEY"),
  stripe_webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET"),
  webhook_paths: ["/webhooks/stripe"]

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