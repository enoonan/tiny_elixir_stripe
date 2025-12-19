# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- `mix tiny_elixir_stripe.set_webhook_path` - Change webhook endpoint path
- `mix tiny_elixir_stripe.update_supported_events` - Update supported Stripe events list
- Support for both function and module-based webhook handlers
- CRUD operations for common Stripe entities (customers, subscriptions, products, prices, etc.)
- Comprehensive test coverage
- Full documentation and guides

[0.0.1]: https://github.com/enoonan/tiny_elixir_stripe/releases/tag/v0.0.1
