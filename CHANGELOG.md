# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.2] - 2026-01-06

### Fixed 

- **Nested parameters cause Protocol.UndefinedError**: [issue 2](https://github.com/enoonan/pin_stripe/issues/2) closed by [PR 3](https://github.com/enoonan/pin_stripe/pull/3) from [neilberkman](https://github.com/neilberkman). Thank you Neil! 🎉

## [0.3.0] - 2025-12-19

### Changed

**⚠️ BREAKING CHANGE**: Simplified webhook handler architecture

Webhook event handlers are now defined directly in your `WebhookController` instead of a separate `WebhookHandler` module. This reduces indirection and simplifies the overall architecture.

**Before (0.2.x)**:
```elixir
defmodule MyApp.StripeWebhookHandlers do
  use PinStripe.WebhookHandler
  
  handle "customer.created", fn event -> ... end
end

defmodule MyAppWeb.StripeWebhookController do
  use PinStripe.WebhookController,
    handler: MyApp.StripeWebhookHandlers
end
```

**After (0.3.0)**:
```elixir
defmodule MyAppWeb.StripeWebhookController do
  use PinStripe.WebhookController
  
  handle "customer.created", fn event -> ... end
end
```

**Migration**: Move your `handle` declarations from your `WebhookHandler` module into your `WebhookController`. Handler modules (for complex handlers) should remain in `lib/my_app/stripe_webhook_handlers/` but are now referenced directly from the controller.

## [0.2.2] - 2025-12-19

### Added

- **`PinStripe.Test.Fixtures`** - Module for loading realistic Stripe test data
  - Error fixtures for all HTTP error codes (400, 401, 403, 404, 429, 500, etc.)
  - API resource fixtures with caching support
  - `mix pin_stripe.sync_api_version` task for fixture version management
- **`PinStripe.Test.Mock`** - High-level mocking helpers for Stripe API testing
  - `stub_read/2` - Stub read operations by ID or entity type
  - `stub_create/2` - Stub create operations by entity type
  - `stub_update/2` - Stub update operations by ID
  - `stub_delete/2` - Stub delete operations by ID
  - `stub_error/3` - Stub error responses for any operation

## [0.2.1] - 2025-12-19

### Fixed
 - **Webhook handler generator bug**: original implementation used text search to validate handler didn't already exist, which picked up examples in the @doc tag.

## [0.2.0] - 2025-12-19

### Changed

**🎉 Complete rebrand from TinyElixirStripe to PinStripe!**

The library has been rebranded with a new name that better reflects its sharp, professional approach to Stripe integration. Inspired by the pinstripe suit - clean, elegant, and professional.

- **Package name**: `tiny_elixir_stripe` → `pin_stripe`
- **Module namespace**: `TinyElixirStripe` → `PinStripe`
- **Config atoms**: `:tiny_elixir_stripe` → `:pin_stripe`
- **Mix tasks**: `mix tiny_elixir_stripe.*` → `mix pin_stripe.*`

This is a **breaking change**. If you're upgrading from TinyElixirStripe:
1. Update your `mix.exs` dependency from `:tiny_elixir_stripe` to `:pin_stripe`
2. Replace all `TinyElixirStripe` module references with `PinStripe`
3. Update config keys from `:tiny_elixir_stripe` to `:pin_stripe`
4. Update mix task calls (e.g., `mix pin_stripe.install` instead of `mix tiny_elixir_stripe.install`)

## [0.0.2] - 2025-12-18

### Added
 - Docs with HexDocs
 - This changelog
 - Hex publish configurations

## [0.0.1] - 2025-12-18

### Added
- Initial release
- Stripe API client built on Req with automatic ID prefix recognition
- Webhook handler DSL using Spark
- Automatic webhook signature verification
- `mix tiny_elixir_stripe.install` - Igniter-powered installation task
- `mix tiny_elixir_stripe.gen.handler` - Generate webhook event handlers
- `mix tiny_elixir_stripe.sync_webhook_handlers` - Sync handlers with Stripe dashboard
- `mix tiny_elixir_stripe.update_supported_events` - Update supported Stripe events list
- Support for both function and module-based webhook handlers
- CRUD operations for common Stripe entities (customers, subscriptions, products, prices, etc.)
- Comprehensive test coverage
- Full documentation and guides

[0.0.1]: https://github.com/enoonan/tiny_elixir_stripe/releases/tag/v0.0.1
