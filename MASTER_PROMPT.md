# TinyElixirStripe - Master Development Prompt

## 🚨 CRITICAL: TEST-DRIVEN DEVELOPMENT REQUIRED 🚨

**YOU MUST ALWAYS WRITE TESTS FIRST BEFORE IMPLEMENTING ANY FEATURE OR CHANGE.**

This is a non-negotiable requirement for this project. The workflow is:

1. **Write the test first** - Define what success looks like
2. **Run the test** - Verify it fails (red)
3. **Implement the feature** - Write the minimum code to pass the test
4. **Run the test again** - Verify it passes (green)
5. **Refactor if needed** - Improve code while keeping tests green

**Never implement functionality without a failing test first. No exceptions.**

## Project Overview
TinyElixirStripe is a minimal Stripe SDK for Elixir that aims to cover 95% of common use cases while providing an escape hatch to Req for advanced scenarios. The project is inspired by Dashbit's "SDKs with Req: Stripe" approach and leverages modern Elixir tooling.

## Core Architecture & Philosophy

### Design Principles
1. **Minimal Surface Area**: Focus on the most common Stripe operations
2. **Req-based**: Built on Req for HTTP requests with proper escape hatches
3. **Idiomatic Elixir**: Follow Elixir conventions and OTP patterns
4. **Code Generation Ready**: Designed to work with Igniter for setup
5. **DSL-friendly**: Uses Spark for webhook handler DSLs

### Key Dependencies
- **Req** (~> 0.5.0): Core HTTP client
- **Spark** (~> 2.3): DSL framework for webhook handlers
- **Igniter** (~> 0.6): Code generation and project patching
- **Usage Rules** (~> 0.1): Development tooling and guidelines

## Current Implementation Status

### What's Implemented
- ✅ Fixed module naming and structure (`TinyElixirStripe.Client`)
- ✅ Basic Stripe client in `lib/client.ex`
- ✅ URL parsing for common Stripe resource IDs
- ✅ Req-based request handling with GET→POST conversion for API calls
- ✅ Proper Req.Test integration for testing with stubs
- ✅ Proper error handling with `{:ok, response}`/`{:error, response}` tuples
- ✅ Complete CRUD functions: `read/2`, `create/3`, `update/3`, `delete/2`
- ✅ Bang versions of all CRUD functions: `read!/2`, `create!/3`, `update!/3`, `delete!/2`
- ✅ `read/2` function supports both string IDs and atom entity types
- ✅ `create/3` function uses atom entity types (`:customers`, `:products`, etc.)
- ✅ Entity type atoms for listing and creating resources
- ✅ Error handling for unrecognized entity types (`:unrecognized_entity_type`)
- ✅ All CRUD functions derive entity type from ID or entity atom
- ✅ Comprehensive test coverage for all CRUD operations using Req.Test
- ✅ Form-encoded body for POST requests (Stripe API standard)
- ✅ Query parameter support for list operations
- ✅ Comprehensive moduledoc with usage examples
- ✅ Function-level documentation with @doc for all functions
- ✅ Doctests for all public functions (11 doctests)
- ✅ Doctests integrated into test suite
- ✅ Test coverage for bang functions with error raising behavior
- ✅ Webhook handling system with Spark DSL
- ✅ Webhook controller base module with `__using__` macro
- ✅ Webhook signature verification
- ✅ Igniter installer for Phoenix integration
- ✅ Generated user-facing webhook controller
- ✅ Automatic handler module creation
- ✅ Router integration with configurable webhook paths

### What Needs Implementation
1. **Test helpers** for Req mocking
2. **Stripe Connect support**
3. **Documentation and examples**
4. **Additional webhook event types**
5. **More comprehensive usage guides**

## Implementation Roadmap

### Phase 1: Core API Client ✅ COMPLETE
- ✅ Fix module naming and structure
- ✅ Add CRUD functions (read, create, update, delete) for common resources
- ✅ Implement proper error handling with `{:ok, result}`/`{:error, reason}` tuples
- ✅ Add configuration management for API keys
- ✅ Refactor `get` to `read` with support for entity type atoms
- ✅ Add list functionality via `read(:entity_type)` with query params
- ✅ Add comprehensive documentation with @moduledoc, @doc, and doctests
- ✅ Integrate doctests into test suite

### Phase 2: Webhook System ✅ COMPLETE
- ✅ Create Spark DSL for webhook handlers
- ✅ Implement webhook controller base module with `__using__` macro
- ✅ Add signature verification
- ✅ Add Igniter installer for webhook endpoint setup
- ✅ Generate user-facing controller that uses base controller
- ✅ Create stub handler module during installation
- ✅ Support for configurable routes

### Phase 3: Developer Experience
- Igniter installers for Phoenix integration
- Test helpers and mock generators
- Comprehensive documentation
- Examples and guides

### Phase 4: Advanced Features
- Stripe Connect support
- OAuth flow handling
- Advanced webhook patterns

## Code Style & Conventions

### Elixir Guidelines
- Follow all usage_rules from AGENTS.md
- Use pattern matching over conditionals
- Implement proper error handling with tuples
- Use `with` for chaining operations
- Prefer multiple function clauses
- Use descriptive function names
- Implement proper guard clauses

### Project Structure
```
lib/
  tiny_elixir_stripe.ex              # Main public API
  tiny_elixir_stripe/
    client.ex                        # Core HTTP client
    webhook_handler.ex               # Spark DSL for webhooks
    webhook_controller.ex            # Base webhook controller
    igniter/                         # Code generators
      install.ex
      webhook.ex
    test_helpers.ex                  # Test utilities
```

### Configuration
- Use Application environment for API keys
- Support runtime configuration
- Provide sensible defaults

## Testing Strategy
- Unit tests for all core functions using Req.Test
- Use `Req.Test.stub/2` for test stubs with concurrent test support
- Configure test environment with `plug: {Req.Test, TinyElixirStripe}`
- Use helper functions like `Req.Test.json/2` for responses
- Integration tests with Stripe test API
- Webhook signature verification tests
- Property tests for URL parsing

### Req.Test Setup
Tests should configure the application to use Req.Test stubs:
```elixir
setup do
  Application.put_env(:tiny_elixir_stripe, :req_options, plug: {Req.Test, TinyElixirStripe})
  :ok
end
```

Then use `Req.Test.stub/2` in tests:
```elixir
test "fetches a customer" do
  Req.Test.stub(TinyElixirStripe, fn conn ->
    Req.Test.json(conn, %{id: "cus_123"})
  end)
  
  result = Client.get("cus_123")
  assert {:ok, %{body: %{"id" => "cus_123"}}} = result
end
```

## Documentation Requirements
- Comprehensive @moduledoc for all modules
- Function documentation with examples
- Installation guides for both Igniter and manual setup
- Webhook integration walkthroughs
- Migration guides from Stripity Stripe

## Key Implementation Details

### CRUD Function Design

#### Read Function
The `read/2` function is polymorphic and handles both individual resource retrieval and list operations:

**Fetch by ID (string):**
```elixir
Client.read("cus_123")  # Returns single customer
Client.read("product_abc123")  # Returns single product
```

**List by entity type (atom):**
```elixir
Client.read(:customers)  # Returns list of customers
Client.read(:products, limit: 10)  # Returns list with query params
```

#### Create Function
The `create/3` function uses atom entity types for consistency:

```elixir
Client.create(:customers, %{email: "user@example.com", name: "John"})
Client.create(:products, %{name: "Widget", price: 1000})
```

#### Update Function
The `update/3` function uses string IDs (derives entity from ID prefix):

```elixir
Client.update("cus_123", %{name: "Jane Doe"})
Client.update("product_abc", %{price: 2000})
```

#### Delete Function
The `delete/2` function uses string IDs:

```elixir
Client.delete("cus_123")
Client.delete("product_abc")
```

**Supported entity types:**
- `:customers` → `/customers`
- `:products` → `/products`
- `:prices` → `/prices`
- `:subscriptions` → `/subscriptions`
- `:invoices` → `/invoices`
- `:events` → `/events`
- `:checkout_sessions` → `/checkout/sessions`

**Error handling:**
- Unrecognized entity types return `{:error, :unrecognized_entity_type}`
- HTTP errors return `{:error, response}` with status and body

### URL Parsing Enhancement
The URL parsing uses ID prefixes to determine resource types:
- `cus_*` → `/customers/{id}`
- `product_*` → `/products/{id}`
- `price_*` → `/prices/{id}`
- `sub_*` → `/subscriptions/{id}`
- `inv_*` → `/invoices/{id}`
- `evt_*` → `/events/{id}`
- `cs_*` → `/checkout/sessions/{id}`

### Error Handling
All API calls should return `{:ok, result}` or `{:error, reason}` tuples. Never raise exceptions for expected API errors.

### Webhook DSL Design
The Spark DSL should support:
- Event type matching
- Function or module handlers
- Data extraction and transformation
- Error handling for webhook processing

### Igniter Integration
- Phoenix route injection
- Controller generation
- Configuration setup
- Dependency management

## Development Workflow
1. **TDD Approach**: Write tests first, then implementation
2. Always run `mix test` after changes
3. Use `mix format` for code formatting
4. Consult `mix usage_rules.docs` for dependency questions
5. Follow semantic versioning
6. Update CHANGELOG for significant changes

## TDD Strategy
- Write failing tests for each feature before implementation
- Use Req mocks for HTTP client testing
- Test both success and error scenarios
- Focus on one function/test at a time
- Ensure all tests pass before moving to next feature

## Quality Assurance
- Maintain 100% test coverage for core functions
- Use dialyzer for type checking
- Follow hex.pm publishing guidelines
- Ensure compatibility with supported Elixir versions

## Future Considerations
- Stripe API versioning strategy
- Backward compatibility guarantees
- Performance optimization for high-throughput scenarios
- Monitoring and observability features

This prompt should guide all development decisions for the TinyElixirStripe project, ensuring consistency with Elixir best practices and the project's minimalist philosophy.