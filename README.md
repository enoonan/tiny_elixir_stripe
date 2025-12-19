# TinyElixirStripe

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

Add `tiny_elixir_stripe` to your `mix.exs`:

```elixir
def deps do
  [
    {:tiny_elixir_stripe, "~> 0.1.3"},
    {:igniter, "~> 0.6"}  # Optional but recommended for code generation
  ]
end
```

### Quick Setup with Igniter

The fastest way to get started is using the Igniter installer:

```bash
mix tiny_elixir_stripe.install 
```

This will:
1. Replace `Plug.Parsers` with `TinyElixirStripe.ParsersWithRawBody` in your Phoenix endpoint, used for verifying incoming webhook signatures
2. Create a `StripeWebhookHandlers` module for defining event handlers
3. Generate a `StripeWebhookController` in your Phoenix app
4. Add the webhook route to your router at the specified path
5. Configure `.formatter.exs` for DSL formatting support

Configure your Stripe API key in `config/config.exs`:

```elixir
config :tiny_elixir_stripe,
  stripe_api_key: System.get_env("STRIPE_SECRET_KEY")
```

### Changing the Webhook Path

The default webhook path is `/webhooks/stripe`. If you need to change it later:

```bash
mix tiny_elixir_stripe.set_webhook_path /new/webhook/path
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
plug TinyElixirStripe.ParsersWithRawBody,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  json_decoder: Jason
```

2. **Create a webhook handler module** (`lib/my_app/stripe_webhook_handlers.ex`):

```elixir
defmodule MyApp.StripeWebhookHandlers do
  use TinyElixirStripe.WebhookHandler

  # Define your handlers here (see examples below)
end
```

3. **Create a webhook controller** (`lib/my_app_web/controllers/stripe_webhook_controller.ex`):

```elixir
defmodule MyAppWeb.StripeWebhookController do
  use TinyElixirStripe.WebhookController,
    handler: MyApp.StripeWebhookHandlers
end
```

4. **Add the route** to your router (`lib/my_app_web/router.ex`):

```elixir
scope "/webhooks" do
  post "/stripe", MyAppWeb.StripeWebhookController, :create
end
```

5. **Add formatter config** to `.formatter.exs`:

```elixir
[
  import_deps: [:tiny_elixir_stripe],
  # ... rest of config
]
```

## Handling Stripe Webhooks

TinyElixirStripe provides a clean DSL for handling webhook events. When Stripe sends a webhook to your endpoint, the controller automatically:
- Verifies the webhook signature using your signing secret
- Parses the event
- Dispatches it to the appropriate handler

### Function Handlers

Define inline handlers for simple event processing:

```elixir
defmodule MyApp.StripeWebhookHandlers do
  use TinyElixirStripe.WebhookHandler

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

For more complex event processing, use separate modules:

```elixir
defmodule MyApp.StripeWebhookHandlers do
  use TinyElixirStripe.WebhookHandler

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
mix tiny_elixir_stripe.gen.handler customer.created

# Generates a module handler
mix tiny_elixir_stripe.gen.handler customer.subscription.created --handler-type module

# Generates with custom module name
mix tiny_elixir_stripe.gen.handler charge.succeeded --handler-type module --module MyApp.Payments.ChargeHandler
```

The generator will:
- Validate the event name against supported Stripe events
- Create the handler in your `WebhookHandler` module
- Generate a separate module file for module handlers

### Syncing with Stripe

Keep your local handlers in sync with your Stripe webhook configuration:

```bash
mix tiny_elixir_stripe.sync_webhook_handlers
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

The `TinyElixirStripe.Client` module provides a simple CRUD interface for interacting with the Stripe API, built on Req.

### Basic Usage

```elixir
alias TinyElixirStripe.Client

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

### Testing

Configure Req.Test for testing:

```elixir
# config/test.exs
config :tiny_elixir_stripe,
  req_options: [plug: {Req.Test, TinyElixirStripe}]
```

In your tests:

```elixir
test "creates a customer" do
  Req.Test.stub(TinyElixirStripe, fn conn ->
    Req.Test.json(conn, %{
      id: "cus_test_123",
      email: "test@example.com",
      object: "customer"
    })
  end)

  {:ok, response} = Client.create(:customers, %{email: "test@example.com"})
  assert response.body["id"] == "cus_test_123"
end
```

## Configuration

```elixir
# config/config.exs
config :tiny_elixir_stripe,
  stripe_api_key: System.get_env("STRIPE_SECRET_KEY"),
  stripe_webhook_signing_secret: System.get_env("STRIPE_WEBHOOK_SECRET")

# config/test.exs  
config :tiny_elixir_stripe,
  req_options: [plug: {Req.Test, TinyElixirStripe}]
```

****

## Special Thanks
 * [Stripity Stripe](https://github.com/beam-community/stripity-stripe)
 * Wojtek Mach
 * Dashbit
 * Zach Daniel and the Ash Team
 * All contributors to [this discussion](https://elixirforum.com/t/is-stripity-stripe-maintained)