# TinyElixirStripe Usage Guide

## Syncing Webhook Handlers with Stripe

The `mix tiny_elixir_stripe.sync_webhook_handlers` task helps keep your local webhook handlers in sync with your Stripe webhook configuration.

### Prerequisites

1. Install the Stripe CLI:
   ```bash
   # macOS
   brew install stripe/stripe-cli/stripe
   
   # Other platforms: https://stripe.com/docs/stripe-cli#install
   ```

2. Authenticate with Stripe:
   ```bash
   stripe login
   ```

### Basic Usage

```bash
mix tiny_elixir_stripe.sync_webhook_handlers
```

The task will:
1. Fetch all webhook endpoints from your Stripe account
2. Extract enabled events from those endpoints
3. Compare with existing handlers in your WebhookHandler module
4. Offer to generate handlers for any missing events

### Example Output

```
Fetching webhook endpoints from Stripe...

Found 2 webhook endpoint(s):
  • https://app.example.com/webhooks/stripe (6 events)
  • https://localhost:4000/webhooks/stripe (3 events)

Collecting all enabled events...

Found WebhookHandler module: MyApp.StripeWebhookHandlers

Events configured in Stripe:
  ✓ customer.created (handler exists)
  ✗ customer.updated (missing)
  ✗ customer.deleted (missing)
  ✓ charge.succeeded (handler exists)
  ✗ charge.failed (missing)
  ✓ invoice.paid (handler exists)

Found 3 missing handler(s) out of 6 total Stripe event(s).

Generate handlers for missing events? [Y/n] y

What type of handlers would you like to generate?
  [1] function
  [2] module
  [3] ask
Choice: 1

Generating handlers...
  • customer.updated (function handler)
  • customer.deleted (function handler)
  • charge.failed (function handler)

✓ Done! Generated 3 new handler(s).
```

### Command Options

#### `--api-key` or `-k`
Specify a Stripe API key directly:
```bash
mix tiny_elixir_stripe.sync_webhook_handlers --api-key sk_test_...
```

If not provided, the task will:
- Look for a key in your application config (`:stripe_api_key`)
- Prompt you to confirm using that key
- Or ask you to enter one manually

#### `--handler-type` or `-t`
Pre-select the handler type without prompting:
```bash
# Generate all as function handlers
mix tiny_elixir_stripe.sync_webhook_handlers --handler-type function

# Generate all as module handlers
mix tiny_elixir_stripe.sync_webhook_handlers --handler-type module

# Ask for each event individually
mix tiny_elixir_stripe.sync_webhook_handlers --handler-type ask
```

#### `--skip-confirmation` or `-y`
Skip all confirmation prompts (useful for automation):
```bash
mix tiny_elixir_stripe.sync_webhook_handlers -y --handler-type function
```

#### `--create-handler-module`
If no WebhookHandler module exists, specify the module name to create:
```bash
mix tiny_elixir_stripe.sync_webhook_handlers \
  --create-handler-module MyApp.StripeWebhookHandlers
```

### Use Cases

#### 1. Initial Setup
After configuring webhook endpoints in Stripe Dashboard, generate all handlers at once:
```bash
mix tiny_elixir_stripe.sync_webhook_handlers --handler-type function
```

#### 2. After Adding Events in Stripe
When you add new events to an existing webhook endpoint:
```bash
mix tiny_elixir_stripe.sync_webhook_handlers
```

#### 3. Development vs Production
Use different API keys to sync against different environments:
```bash
# Development
mix tiny_elixir_stripe.sync_webhook_handlers --api-key $DEV_STRIPE_KEY

# Production
mix tiny_elixir_stripe.sync_webhook_handlers --api-key $PROD_STRIPE_KEY
```

This is a read-only operation that will create stub handlers based on the result of `stripe webhook_endpoints list` with the provided key. 

### How It Works

The task uses Igniter's `compose_task` feature to leverage the existing `gen.handler` task:

1. **Fetches webhook data** - Calls `stripe webhook_endpoints list` via CLI
2. **Parses events** - Extracts unique events from all webhook endpoints
3. **Finds existing handlers** - Scans your WebhookHandler module for existing `handle` calls
4. **Compares** - Identifies which Stripe events don't have handlers
5. **Generates handlers** - Calls `gen.handler` for each missing event
6. **No duplication** - Handlers are only generated if they don't already exist

### Troubleshooting

#### Stripe CLI not found
```
Error: Stripe CLI is not installed or not in your PATH.
```
**Solution**: Install the Stripe CLI following the [official guide](https://stripe.com/docs/stripe-cli#install)

#### Not authenticated
```
Error: Stripe CLI is not authenticated.
```
**Solution**: Run `stripe login` to authenticate

#### API key invalid
```
Error: Failed to fetch webhook endpoints from Stripe.
```
**Solution**: Verify your API key is valid and has the correct permissions

#### No webhook endpoints found
If you see "Found 0 webhook endpoint(s)", check:
- You're using the correct API key (test vs live mode)
- Webhook endpoints are configured in Stripe Dashboard
- Your API key has permission to list webhook endpoints

### Related Tasks

- `mix tiny_elixir_stripe.gen.handler` - Manually generate a handler for a specific event
- `mix tiny_elixir_stripe.install` - Initial setup of TinyElixirStripe
- `mix tiny_elixir_stripe.set_webhook_path` - Change the webhook endpoint path
