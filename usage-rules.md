# PinStripe Usage Rules

A minimal Stripe SDK for Elixir with webhook handling, built on Req and Spark.

## Installation

### Using Igniter (Recommended)

Install using the Igniter installer, which handles everything automatically:

```bash
mix igniter.install pin_stripe
```

This automatically:
- Adds the dependency to your `mix.exs`
- Configures your Phoenix endpoint for webhook signature verification
- Creates webhook handler and controller modules
- Sets up routing
- Configures code formatting

### Manual Installation

If not using Igniter, add to your `mix.exs`:

```elixir
{:pin_stripe, "~> 0.1"}
```

Then manually configure endpoints, handlers, and routes (see Manual Setup section in README).

## Configuration

Configure your Stripe credentials. Typically done in `config/runtime.exs`:

```elixir
config :pin_stripe,
  stripe_api_key: System.get_env("YOUR_STRIPE_KEY_ENV_VAR"),
  stripe_webhook_secret: System.get_env("YOUR_WEBHOOK_SECRET_ENV_VAR")
```

**Required configuration keys:**
- `:pin_stripe, :stripe_api_key` - Your Stripe API key for making requests
- `:pin_stripe, :stripe_webhook_secret` - Your webhook signing secret for verifying webhooks

**Important**: Never commit API keys to version control. Always use environment variables or a secrets manager.

## Making API Requests

Use `PinStripe.request/2` to make Stripe API calls:

```elixir
# GET request
{:ok, customer} = PinStripe.request(:get, "/v1/customers/cus_123")

# POST request with params
{:ok, customer} = PinStripe.request(:post, "/v1/customers", 
  email: "customer@example.com",
  name: "Jane Doe"
)

# DELETE request
{:ok, _} = PinStripe.request(:delete, "/v1/customers/cus_123")
```

All requests return `{:ok, response}` or `{:error, reason}` tuples.

## Webhook Handling

### WebhookHandler Module

The installer creates a `StripeWebhookHandlers` module. Define handlers using the DSL:

```elixir
defmodule MyApp.StripeWebhookHandlers do
  use PinStripe.WebhookHandler

  # Function handler - inline
  handle "customer.created", fn event ->
    customer = event.data.object
    # Handle the event
    :ok
  end

  # Module handler - separate module
  handle "invoice.paid", MyApp.InvoicePaidHandler
end
```

**Important**: 
- Always return `:ok` from handlers to acknowledge successful processing
- Return `{:error, reason}` to indicate processing failure (webhook will be retried by Stripe)
- The `event` parameter contains the full Stripe event object

### Handler Types

**Function Handlers** - Quick inline handlers:
```elixir
handle "customer.updated", fn event ->
  # Process event inline
  :ok
end
```

**Module Handlers** - Better for complex logic:
```elixir
# In your WebhookHandler module
handle "subscription.created", MyApp.SubscriptionCreatedHandler

# Separate module
defmodule MyApp.SubscriptionCreatedHandler do
  def handle_event(event) do
    subscription = event.data.object
    # Complex processing logic
    :ok
  end
end
```

### Generating Handlers

Use the generator to create handlers quickly:

```bash
# Generate a function handler
mix pin_stripe.gen.handler customer.subscription.updated

# Generate a module handler
mix pin_stripe.gen.handler invoice.paid --handler-type module
```

### Webhook Controller

The installer creates `lib/my_app_web/stripe_webhook_controller.ex` which:
- Verifies webhook signatures automatically
- Routes events to your handlers
- Handles errors gracefully

**Note**: The controller is created in `lib/my_app_web/`, not in `lib/my_app_web/controllers/`. You can move it to the controllers directory if preferred.

### Security

The installer configures `PinStripe.ParsersWithRawBody` in your endpoint, which:
- Caches the raw request body for signature verification
- Is required for Stripe webhook security
- Replaces the standard `Plug.Parsers`

**Critical**: Never skip webhook signature verification in production. The installer handles this automatically.

## Common Patterns

### Idempotent Webhook Processing

Stripe may send the same webhook multiple times. Make your handlers idempotent:

```elixir
handle "payment_intent.succeeded", fn event ->
  payment_intent_id = event.data.object.id
  
  # Check if already processed
  case MyApp.Payments.get_by_stripe_id(payment_intent_id) do
    nil -> 
      # First time, process it
      MyApp.Payments.create_from_stripe(event.data.object)
      :ok
    _existing -> 
      # Already processed, skip
      :ok
  end
end
```

### Error Handling

Return errors to have Stripe retry:

```elixir
handle "invoice.payment_failed", fn event ->
  case MyApp.Billing.handle_failed_payment(event.data.object) do
    {:ok, _} -> :ok
    {:error, :temporary_failure} -> {:error, "Database unavailable, retry later"}
    {:error, _reason} -> :ok  # Don't retry for permanent failures
  end
end
```

### Async Processing

For long-running operations, enqueue a job:

```elixir
handle "customer.subscription.deleted", fn event ->
  # Quick acknowledgment, process async
  MyApp.Jobs.queue_subscription_cancellation(event.data.object.id)
  :ok
end
```

## Event Types

Common Stripe events:
- `customer.created`, `customer.updated`, `customer.deleted`
- `payment_intent.succeeded`, `payment_intent.payment_failed`
- `invoice.paid`, `invoice.payment_failed`
- `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`
- `charge.succeeded`, `charge.failed`, `charge.refunded`

View all supported events:
```bash
cat deps/pin_stripe/priv/supported_stripe_events.txt
```

## Testing

PinStripe provides comprehensive test helpers in `PinStripe.Test.Mock` and `PinStripe.Test.Fixtures` for testing your Stripe integration without hitting the real API.

### Test Helpers Overview

**`PinStripe.Test.Mock`** - High-level mocking functions for common operations:
- `stub_read/2` - Mock reading/listing resources
- `stub_create/2` - Mock creating resources
- `stub_update/2` - Mock updating resources
- `stub_delete/1` - Mock deleting resources
- `stub_error/1` or `stub_error/2` - Mock error responses
- `stub_fixture/1` or `stub_fixture/2` - Mock using pre-built fixtures

**`PinStripe.Test.Fixtures`** - Load realistic Stripe response data (can use live API or cached fixtures)

### Basic Mock Usage

```elixir
defmodule MyAppTest do
  use ExUnit.Case
  alias PinStripe.Test.Mock

  test "creates a customer" do
    # Mock the create response
    Mock.stub_create(:customers, %{
      "id" => "cus_123",
      "email" => "test@example.com"
    })

    # Your application code
    {:ok, customer} = MyApp.create_customer("test@example.com")
    
    assert customer["id"] == "cus_123"
  end

  test "reads a customer" do
    Mock.stub_read("cus_123", %{
      "id" => "cus_123",
      "email" => "test@example.com"
    })

    {:ok, customer} = MyApp.get_customer("cus_123")
    
    assert customer["email"] == "test@example.com"
  end

  test "lists customers" do
    Mock.stub_read(:customers, [
      %{"id" => "cus_1", "email" => "user1@example.com"},
      %{"id" => "cus_2", "email" => "user2@example.com"}
    ])

    {:ok, customers} = MyApp.list_customers()
    
    assert length(customers) == 2
  end
end
```

### Testing Error Handling

Use `stub_error/1` with predefined error atoms or `stub_error/2` for custom errors:

```elixir
test "handles not found errors" do
  Mock.stub_error(:not_found)

  assert {:error, %{status: 404}} = MyApp.get_customer("cus_invalid")
end

test "handles rate limiting" do
  Mock.stub_error(:rate_limit)

  assert {:error, %{status: 429}} = MyApp.create_customer("test@example.com")
end

test "handles custom validation errors" do
  Mock.stub_error(:bad_request, %{
    message: "Invalid email address",
    param: "email"
  })

  assert {:error, response} = MyApp.create_customer("invalid")
  assert response.body["error"]["param"] == "email"
end
```

**Available error atoms:**
- `:not_found` (404) - Resource doesn't exist
- `:bad_request` (400) - Missing or invalid parameters
- `:unauthorized` (401) - Invalid API key
- `:rate_limit` (429) - Too many requests
- `:server_error` (500) - Stripe server error

### Using Error Fixtures

For realistic error responses, use `stub_fixture/1` with error atoms:

```elixir
test "handles card declined errors" do
  Mock.stub_fixture(:error_402)

  {:error, response} = MyApp.charge_card(payment_method)
  
  assert response.body["error"]["type"] == "card_error"
  assert response.body["error"]["code"] == "card_declined"
end

test "handles idempotency conflicts" do
  Mock.stub_fixture(:error_409)

  {:error, response} = MyApp.create_payment(idempotency_key: "duplicate")
  
  assert response.body["error"]["type"] == "idempotency_error"
end
```

**Available error fixtures:**
- `:error_400` - Bad Request (missing required parameter)
- `:error_401` - Unauthorized (invalid API key)
- `:error_402` - Request Failed (card declined)
- `:error_403` - Forbidden (insufficient permissions)
- `:error_404` - Not Found (resource doesn't exist)
- `:error_409` - Conflict (idempotency key in use)
- `:error_424` - External Dependency Failed
- `:error_429` - Too Many Requests (rate limit)
- `:error_500`, `:error_502`, `:error_503`, `:error_504` - Server Errors

### Testing with Real Stripe Data

Use fixtures to load real Stripe response data (requires Stripe CLI for first-time generation):

```elixir
test "handles real customer data structure" do
  # Loads actual Stripe customer response (cached after first load)
  Mock.stub_fixture("customer")

  {:ok, customer} = MyApp.get_customer("cus_test")
  
  # Test against real Stripe data structure
  assert Map.has_key?(customer, "id")
  assert Map.has_key?(customer, "email")
  assert customer["object"] == "customer"
end
```

**Fixture Types:**
- **Error Fixtures** - Use atoms (`:error_404`, `:error_400`, etc.), self-contained, no Stripe CLI required
- **API Resources** - Use strings (`"customer"`, `"payment_intent"`), require Stripe CLI for initial generation  
- **Webhook Events** - Use strings (`"customer.created"`), require Stripe CLI

Error fixtures are generated instantly and don't create cached files.

### Testing Webhooks Locally

Use the Stripe CLI to forward webhooks:

```bash
stripe listen --forward-to localhost:4000/webhooks/stripe
```

Trigger test events:

```bash
stripe trigger customer.created
stripe trigger payment_intent.succeeded
```

### Testing Webhook Handlers

Test webhook handlers directly without HTTP:

```elixir
test "handles customer.created event" do
  event = %{
    id: "evt_test",
    type: "customer.created",
    data: %{
      object: %{
        id: "cus_test",
        email: "test@example.com"
      }
    }
  }
  
  assert :ok = MyApp.StripeWebhookHandlers.handle_event(event)
end
```

### Test Setup

In your `test_helper.exs`, configure the test adapter:

```elixir
# Use Req.Test adapter for mocking
Application.put_env(:pin_stripe, :req_options, plug: {Req.Test, PinStripe})
```

This allows `Mock` functions to intercept Stripe API calls in tests.

## Mix Tasks

- `mix pin_stripe.install` - Install and configure PinStripe
- `mix pin_stripe.gen.handler <event>` - Generate a handler for a specific event
- `mix pin_stripe.sync_webhook_handlers` - Sync handlers with Stripe (if using Spark introspection)

## Common Mistakes

- **Don't hardcode API keys**: Always use environment variables
- **Don't skip signature verification**: The installer configures this automatically
- **Don't block webhook handlers**: Keep handlers fast, enqueue long operations
- **Don't forget to return `:ok`**: Handlers must return `:ok` or `{:error, reason}`
- **Don't process webhooks twice**: Make handlers idempotent
- **Don't use in production without testing**: Test with Stripe CLI first

## Best Practices

1. **Keep handlers simple**: Complex logic should be in separate modules
2. **Log webhook processing**: Helpful for debugging
3. **Monitor webhook failures**: Set up alerts for repeated failures
4. **Version your API**: Stripe has multiple API versions, be consistent
5. **Handle all expected events**: Unhandled events are logged but don't cause errors
6. **Test with Stripe CLI**: Always test webhooks before deploying

## Troubleshooting

**Webhook signature verification fails**:
- Check that `ParsersWithRawBody` is configured in your endpoint
- Verify `:pin_stripe, :stripe_webhook_secret` config is set correctly
- Ensure you're using the secret from the Stripe webhook endpoint settings

**Events not being handled**:
- Check handler module is referenced in the WebhookController
- Verify handler is defined for that specific event type
- Check application logs for errors

**API requests failing**:
- Verify `:pin_stripe, :stripe_api_key` config is set
- Check API key has correct permissions
- Ensure you're using the correct API version
