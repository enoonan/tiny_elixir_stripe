defmodule Mix.Tasks.TinyElixirStripe.SyncWebhookHandlers.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc do
    "Sync webhook handlers with Stripe's configured webhook endpoints"
  end

  @spec example() :: String.t()
  def example do
    "mix tiny_elixir_stripe.sync_webhook_handlers"
  end

  @spec long_doc() :: String.t()
  def long_doc do
    """
    #{short_doc()}

    This task will:

    1. Fetch all webhook endpoints from your Stripe account using the Stripe CLI
    2. Extract all enabled events from those endpoints
    3. Compare them with handlers in your WebhookHandler module
    4. Generate handlers for any missing events

    This is useful for keeping your local webhook handlers in sync with your
    Stripe webhook configuration, especially after adding new events in the
    Stripe Dashboard.

    ## Example

    ```sh
    #{example()}
    ```

    ## Options

    * `--api-key` or `-k` - The Stripe API key to use (prompts to use config key if not provided)
    * `--handler-type` or `-t` - Type of handler to generate: "function", "module", or "ask" (default: prompts user)
    * `--skip-confirmation` or `-y` - Skip confirmation prompts and generate all missing handlers
    * `--create-handler-module` - Module name to create if no WebhookHandler module exists

    ## Prerequisites

    This task requires the Stripe CLI to be installed and authenticated:

    ```sh
    # Install Stripe CLI (macOS)
    brew install stripe/stripe-cli/stripe

    # Login to Stripe
    stripe login
    ```

    ## Handler Types

    ### Function Handler (inline)

    Generates inline function handlers in your WebhookHandler module:

    ```elixir
    handle "customer.created", fn event ->
      # Handle customer.created event
      :ok
    end
    ```

    ### Module Handler

    Generates separate modules with a `handle_event/1` function:

    ```elixir
    # In your WebhookHandler module
    handle "customer.created", MyApp.StripeWebhookHandlers.CustomerCreated

    # Generated module
    defmodule MyApp.StripeWebhookHandlers.CustomerCreated do
      def handle_event(event) do
        # Handle customer.created event
        :ok
      end
    end
    ```

    ### Ask (interactive)

    Prompts you for each event individually, allowing you to choose
    function or module handlers on a per-event basis.
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.TinyElixirStripe.SyncWebhookHandlers do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :tiny_elixir_stripe,
        adds_deps: [],
        installs: [],
        example: __MODULE__.Docs.example(),
        only: nil,
        positional: [],
        composes: ["tiny_elixir_stripe.gen.handler"],
        schema: [
          api_key: :string,
          handler_type: :string,
          skip_confirmation: :boolean,
          create_handler_module: :string
        ],
        defaults: [],
        aliases: [k: :api_key, t: :handler_type, y: :skip_confirmation],
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      # Step 1: Get API key
      api_key = resolve_api_key(igniter)

      # Step 2: Fetch events from Stripe
      stripe_events = fetch_webhook_events(api_key)

      # Step 3: Find existing handlers
      {igniter, existing_events} = get_existing_handlers(igniter)

      # Step 4: Find missing events
      missing_events = MapSet.difference(stripe_events, existing_events)

      # Step 5: Display summary
      display_sync_summary(stripe_events, existing_events, missing_events)

      # Step 6: Confirm and get handler type
      if should_generate_handlers?(igniter, missing_events) do
        handler_type_option = get_handler_type_preference(igniter)

        # Step 7: Compose gen.handler for each missing event
        generate_missing_handlers(igniter, missing_events, handler_type_option)
      else
        igniter
      end
    end

    # API Key Resolution

    defp resolve_api_key(igniter) do
      case igniter.args.options[:api_key] do
        # User provided via flag
        key when is_binary(key) ->
          key

        # Try to read from application config
        nil ->
          resolve_api_key_from_config()
      end
    end

    defp resolve_api_key_from_config do
      case fetch_config_api_key() do
        {:ok, config_key} ->
          prompt_to_use_config_key(config_key)

        :error ->
          Mix.shell().info("\nNo API key found in config.")
          prompt_for_api_key()
      end
    end

    defp prompt_to_use_config_key(config_key) do
      masked_key = mask_api_key(config_key)

      if Igniter.Util.IO.yes?(
           "\nNo --api-key provided.\n\nFound API key in config: #{masked_key}\n\nUse this API key?"
         ) do
        config_key
      else
        prompt_for_api_key()
      end
    end

    defp fetch_config_api_key do
      try do
        {:ok, Application.fetch_env!(:tiny_elixir_stripe, :stripe_api_key)}
      rescue
        _ -> :error
      end
    end

    defp mask_api_key(key) do
      if String.length(key) > 12 do
        String.slice(key, 0..11) <> String.duplicate("*", String.length(key) - 12)
      else
        String.duplicate("*", String.length(key))
      end
    end

    defp prompt_for_api_key do
      case Mix.shell().prompt("\nPlease enter your Stripe API key: ") |> String.trim() do
        "" ->
          Mix.shell().error("API key cannot be empty.")
          exit({:shutdown, 1})

        key ->
          key
      end
    end

    # Stripe CLI Integration

    @spec fetch_webhook_events(String.t()) :: MapSet.t(String.t())
    defp fetch_webhook_events(api_key) do
      Mix.shell().info("\nFetching webhook endpoints from Stripe...")

      case System.cmd("stripe", ["webhook_endpoints", "list", "--api-key", api_key],
             stderr_to_stdout: true
           ) do
        {output, 0} ->
          parse_webhook_events(output)

        {output, _exit_code} ->
          handle_stripe_cli_error(output)
      end
    end

    defp parse_webhook_events(json_output) do
      case JSON.decode(json_output) do
        {:ok, %{"data" => endpoints}} when is_list(endpoints) ->
          endpoint_count = length(endpoints)

          Mix.shell().info("\nFound #{endpoint_count} webhook endpoint(s):")

          endpoints
          |> Enum.each(fn endpoint ->
            url = endpoint["url"]
            event_count = length(endpoint["enabled_events"] || [])
            Mix.shell().info("  • #{url} (#{event_count} events)")
          end)

          Mix.shell().info("\nCollecting all enabled events...")

          events =
            endpoints
            |> Enum.flat_map(fn endpoint ->
              endpoint["enabled_events"] || []
            end)
            |> MapSet.new()

          events

        {:error, error} ->
          Mix.shell().error("\nFailed to parse Stripe API response: #{inspect(error)}")
          exit({:shutdown, 1})

        _ ->
          Mix.shell().error("\nUnexpected response format from Stripe API")
          exit({:shutdown, 1})
      end
    end

    defp handle_stripe_cli_error(output) do
      cond do
        String.contains?(output, "command not found") or
            String.contains?(output, "stripe: not found") ->
          Mix.shell().error("""

          Stripe CLI is not installed or not in your PATH.

          Please install the Stripe CLI:

            # macOS
            brew install stripe/stripe-cli/stripe

            # Linux
            See: https://stripe.com/docs/stripe-cli#install

            # Windows
            See: https://stripe.com/docs/stripe-cli#install

          Then authenticate:

            stripe login
          """)

        String.contains?(output, "not authenticated") or
          String.contains?(output, "login") or
            String.contains?(output, "API key") ->
          Mix.shell().error("""

          Stripe CLI is not authenticated.

          Please login to Stripe:

            stripe login

          Or provide a valid API key using --api-key
          """)

        true ->
          Mix.shell().error("""

          Failed to fetch webhook endpoints from Stripe.

          Error output:
          #{output}

          Please ensure:
          1. The Stripe CLI is installed: https://stripe.com/docs/stripe-cli
          2. You are authenticated: stripe login
          3. Your API key is valid
          """)
      end

      exit({:shutdown, 1})
    end

    # Existing Handler Extraction

    @spec get_existing_handlers(Igniter.t()) :: {Igniter.t(), MapSet.t(String.t())}
    defp get_existing_handlers(igniter) do
      {igniter, events_list} =
        case find_webhook_handler_module(igniter) do
          {igniter, nil} ->
            # No handler module found
            Mix.shell().info("\nNo WebhookHandler module found.")
            {igniter, []}

          {igniter, module} ->
            case Igniter.Project.Module.find_module(igniter, module) do
              {:ok, {igniter, source, _zipper}} ->
                content = Rewrite.Source.get(source, :content)
                events = extract_event_names_from_source(content)
                Mix.shell().info("\nFound WebhookHandler module: #{inspect(module)}")
                {igniter, events}

              _ ->
                {igniter, []}
            end
        end

      {igniter, MapSet.new(events_list)}
    end

    defp find_webhook_handler_module(igniter) do
      # Search all .ex files in the project for modules using TinyElixirStripe.WebhookHandler
      found_module =
        igniter.rewrite
        |> Rewrite.sources()
        |> Enum.find_value(&find_handler_in_source/1)

      {igniter, found_module}
    end

    defp find_handler_in_source(source) do
      path = Rewrite.Source.get(source, :path)

      with true <- Path.extname(path) == ".ex",
           content <- Rewrite.Source.get(source, :content),
           true <- content =~ "use TinyElixirStripe.WebhookHandler",
           [_, module_name] <- Regex.run(~r/defmodule\s+([\w.]+)/, content) do
        Module.concat([module_name])
      else
        _ -> nil
      end
    end

    defp extract_event_names_from_source(content) do
      # Use regex to find all: handle "event.name", ...
      ~r/handle\s+"([^"]+)"/
      |> Regex.scan(content, capture: :all_but_first)
      |> List.flatten()
    end

    # Summary Display

    defp display_sync_summary(stripe_events, existing_events, missing_events) do
      all_events = MapSet.union(stripe_events, existing_events) |> Enum.sort()

      Mix.shell().info("\nEvents configured in Stripe:")

      if Enum.empty?(all_events) do
        Mix.shell().info("  (no events found)")
      else
        Enum.each(all_events, fn event ->
          display_event_status(event, stripe_events, existing_events)
        end)
      end

      stripe_count = MapSet.size(stripe_events)
      missing_count = MapSet.size(missing_events)

      Mix.shell().info(
        "\nFound #{missing_count} missing handler(s) out of #{stripe_count} total Stripe event(s)."
      )
    end

    defp display_event_status(event, stripe_events, existing_events) do
      cond do
        MapSet.member?(stripe_events, event) and MapSet.member?(existing_events, event) ->
          Mix.shell().info("  ✓ #{event} (handler exists)")

        MapSet.member?(stripe_events, event) ->
          Mix.shell().info("  ✗ #{event} (missing)")

        true ->
          Mix.shell().info("  ℹ #{event} (handler exists but not in Stripe)")
      end
    end

    # Handler Generation Decision

    defp should_generate_handlers?(igniter, missing_events) do
      if MapSet.size(missing_events) == 0 do
        Mix.shell().info("\n✓ All Stripe events have handlers! Nothing to do.")
        false
      else
        if igniter.args.options[:skip_confirmation] do
          true
        else
          Igniter.Util.IO.yes?("\nGenerate handlers for missing events?")
        end
      end
    end

    defp get_handler_type_preference(igniter) do
      case igniter.args.options[:handler_type] do
        nil ->
          # Prompt user
          Igniter.Util.IO.select(
            "\nWhat type of handlers would you like to generate?",
            ["function", "module", "ask"]
          )

        type when type in ["function", "module", "ask"] ->
          type

        type ->
          Mix.shell().error("""
          Invalid handler type: #{type}

          Valid options are: "function", "module", or "ask"
          """)

          exit({:shutdown, 1})
      end
    end

    # Handler Generation with Composition

    defp generate_missing_handlers(igniter, missing_events, handler_type_option) do
      Mix.shell().info("\nGenerating handlers...")

      missing_events
      |> Enum.sort()
      |> Enum.reduce(igniter, fn event, acc ->
        # Determine handler type for this event
        handler_type =
          case handler_type_option do
            "ask" ->
              Igniter.Util.IO.select(
                "\nHandler type for \"#{event}\":",
                ["function", "module"]
              )

            type ->
              type
          end

        # Build argv for gen.handler
        argv = build_gen_handler_argv(event, handler_type, acc)

        # Show what we're generating
        handler_type_display = if handler_type == "function", do: "function", else: "module"
        Mix.shell().info("  • #{event} (#{handler_type_display} handler)")

        # Compose the gen.handler task
        Igniter.compose_task(acc, "tiny_elixir_stripe.gen.handler", argv)
      end)
      |> tap(fn _ ->
        Mix.shell().info("\n✓ Done! Generated #{MapSet.size(missing_events)} new handler(s).")
      end)
    end

    defp build_gen_handler_argv(event, handler_type, igniter) do
      argv = [event, "--handler-type", handler_type]

      # Pass through create_handler_module if specified
      if module = igniter.args.options[:create_handler_module] do
        argv ++ ["--create-handler-module", module]
      else
        argv
      end
    end
  end
else
  defmodule Mix.Tasks.TinyElixirStripe.SyncWebhookHandlers do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'tiny_elixir_stripe.sync_webhook_handlers' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
