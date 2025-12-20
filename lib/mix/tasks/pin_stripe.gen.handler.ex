defmodule Mix.Tasks.PinStripe.Gen.Handler.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc do
    "Generate a Stripe webhook event handler"
  end

  @spec example() :: String.t()
  def example do
    "mix pin_stripe.gen.handler customer.created"
  end

  @spec long_doc() :: String.t()
  def long_doc do
    """
    #{short_doc()}

    Generates a handler for a specific Stripe webhook event.

    ## Example

    ```sh
    #{example()}
    ```

    ## Arguments

    * `event` - The Stripe event name (e.g., "customer.created", "charge.succeeded")

    ## Options

    * `--handler-type` - Type of handler to generate: "function" or "module" (default: prompts user)
    * `--module` - Custom module name for module handlers (default: auto-generated from event name)
    * `--create-handler-module` - Module name to create if no WebhookHandler module exists

     ## Handler Types

     ### Function Handler

     Generates an inline function handler in your WebhookController:

     ```elixir
     handle "customer.created", fn event ->
       # Handle customer.created event
       :ok
     end
     ```

     ### Module Handler

     Generates a separate module with a `handle_event/1` function:

     ```elixir
     # In your WebhookController
     handle "customer.created", MyAppWeb.StripeWebhookHandlers.CustomerCreated

     # Generated module at lib/my_app_web/stripe_webhook_handlers/customer_created.ex
     defmodule MyAppWeb.StripeWebhookHandlers.CustomerCreated do
       def handle_event(event) do
         # Handle customer.created event
         :ok
       end
     end
     ```
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.PinStripe.Gen.Handler do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :pin_stripe,
        adds_deps: [],
        installs: [],
        example: __MODULE__.Docs.example(),
        only: nil,
        positional: [:event],
        composes: [],
        schema: [
          handler_type: :string,
          module: :string,
          create_handler_module: :string
        ],
        defaults: [],
        aliases: [],
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      event = igniter.args.positional[:event]

      unless event do
        raise ArgumentError, """
        event name is required.

        Usage: mix pin_stripe.gen.handler <event>

        Example: mix pin_stripe.gen.handler customer.created
        """
      end

      # Validate the event name
      unless valid_stripe_event?(event) do
        raise ArgumentError, """
        "#{event}" is not a valid Stripe event.

        Run this command to see all supported events:
        stripe trigger --help

        Or check: priv/supported_stripe_events.txt
        """
      end

      # Find or create the webhook handler module
      {igniter, handler_module} = find_or_create_webhook_handler_module(igniter)

      # Check if handler already exists
      igniter =
        case handler_already_exists?(igniter, handler_module, event) do
          true ->
            Igniter.add_warning(
              igniter,
              ~s(Handler for "#{event}" already exists in #{inspect(handler_module)})
            )

          false ->
            # Get or prompt for handler type
            handler_type = get_handler_type(igniter)

            # Generate the handler
            generate_handler(igniter, handler_module, event, handler_type)
        end

      igniter
    end

    defp valid_stripe_event?(event) do
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

    defp find_or_create_webhook_handler_module(igniter) do
      # Try to find a module that uses PinStripe.WebhookController
      case find_webhook_controller_module(igniter) do
        {igniter, nil} ->
          create_new_webhook_controller_module(igniter)

        {igniter, module} ->
          {igniter, module}
      end
    end

    defp create_new_webhook_controller_module(igniter) do
      # No module found, check if user wants to create one
      case igniter.args.options[:create_handler_module] do
        nil ->
          prompt_for_module_creation(igniter)

        create_module_name ->
          module = Module.concat([create_module_name])
          {create_webhook_controller_module(igniter, module), module}
      end
    end

    defp prompt_for_module_creation(igniter) do
      web_module = Igniter.Libs.Phoenix.web_module(igniter)
      default_module = Module.concat([web_module, "StripeWebhookController"])

      if Igniter.Util.IO.yes?(
           "No WebhookController module found. Create #{inspect(default_module)}?"
         ) do
        {create_webhook_controller_module(igniter, default_module), default_module}
      else
        raise "Cannot generate handler without a WebhookController module"
      end
    end

    defp find_webhook_controller_module(igniter) do
      # First search in rewrite buffer (for test environment and pending changes)
      found_in_rewrite =
        igniter.rewrite
        |> Rewrite.sources()
        |> Enum.find_value(&find_controller_in_source/1)

      case found_in_rewrite do
        nil ->
          # If not found in rewrite buffer, search filesystem
          found_on_disk =
            try do
              lib_path =
                Igniter.Project.Module.proper_location(
                  igniter,
                  Igniter.Project.Module.module_name_prefix(igniter)
                )
                |> Path.dirname()

              Path.wildcard(Path.join([lib_path, "**", "*.ex"]))
              |> Enum.find_value(&find_controller_in_file/1)
            rescue
              _ -> nil
            end

          {igniter, found_on_disk}

        module ->
          {igniter, module}
      end
    end

    defp find_controller_in_source(source) do
      path = Rewrite.Source.get(source, :path)

      with true <- Path.extname(path) == ".ex",
           content <- Rewrite.Source.get(source, :content),
           true <- content =~ "use PinStripe.WebhookController",
           [_, module_name] <- Regex.run(~r/defmodule\s+([\w.]+)/, content) do
        Module.concat([module_name])
      else
        _ -> nil
      end
    end

    defp find_controller_in_file(path) do
      with true <- File.exists?(path),
           {:ok, content} <- File.read(path),
           true <- content =~ "use PinStripe.WebhookController",
           [_, module_name] <- Regex.run(~r/defmodule\s+([\w.]+)/, content) do
        Module.concat([module_name])
      else
        _ -> nil
      end
    end

    defp create_webhook_controller_module(igniter, module) do
      # Check if module already exists in the rewrite sources
      case Igniter.Project.Module.find_module(igniter, module) do
        {:ok, {igniter, _source, _zipper}} ->
          # Module already exists (either on disk or in pending changes), return igniter unchanged
          igniter

        {:error, _} ->
          # Module doesn't exist, create it
          Igniter.Project.Module.create_module(igniter, module, """
          use PinStripe.WebhookController
          """)
      end
    end

    defp handler_already_exists?(igniter, module, event) do
      # Check if handler exists by looking for handle DSL calls in the source
      # We use zipper-based search instead of string matching to avoid false positives
      # from documentation examples
      with {:ok, {_igniter, _source, zipper}} <-
             Igniter.Project.Module.find_module(igniter, module),
           {:ok, _} <- find_handle_call_for_event(zipper, event) do
        true
      else
        _ -> false
      end
    end

    defp find_handle_call_for_event(zipper, event) do
      # Search for handle calls with this event as the first argument
      # handle/2 can be called with either a function or a module
      Igniter.Code.Function.move_to_function_call(
        zipper,
        :handle,
        2,
        &handle_call_matches_event?(&1, event)
      )
    end

    defp handle_call_matches_event?(call_zipper, event) do
      # Check if the first argument is a string matching our event
      with {:ok, arg_zipper} <- Igniter.Code.Function.move_to_nth_argument(call_zipper, 0),
           {_type, _meta, [^event]} <- Sourceror.Zipper.node(arg_zipper) do
        true
      else
        _ -> false
      end
    end

    defp get_handler_type(igniter) do
      case igniter.args.options[:handler_type] do
        nil ->
          # Prompt user
          Igniter.Util.IO.select(
            "What type of handler would you like to generate?",
            ["function", "module"]
          )

        type when type in ["function", "module"] ->
          type

        type ->
          raise ArgumentError, """
          Invalid handler type: #{type}

          Valid options are: "function" or "module"
          """
      end
    end

    defp generate_handler(igniter, handler_module, event, "function") do
      # Generate inline function handler
      add_function_handler(igniter, handler_module, event)
    end

    defp generate_handler(igniter, controller_module, event, "module") do
      # Generate module handler
      custom_module = igniter.args.options[:module]

      handler_module_name =
        if custom_module do
          Module.concat([custom_module])
        else
          # Auto-generate module name from event
          # e.g., "customer.created" -> CustomerCreated
          # Handler modules live under MyApp.StripeWebhookHandlers, not the controller
          app_module = Igniter.Project.Module.module_name_prefix(igniter)
          module_suffix = event_to_module_name(event)
          Module.concat([app_module, "StripeWebhookHandlers", module_suffix])
        end

      igniter
      |> create_handler_module(handler_module_name, event)
      |> add_module_handler(controller_module, event, handler_module_name)
    end

    defp event_to_module_name(event) do
      event
      |> String.split([".", "_"])
      |> Enum.map_join("", &Macro.camelize/1)
    end

    defp add_function_handler(igniter, module, event) do
      handler_code = ~s"""

      handle "#{event}", fn event ->
        # Handle #{event} event
        :ok
      end
      """

      Igniter.Project.Module.find_and_update_module!(igniter, module, fn zipper ->
        case Igniter.Code.Module.move_to_use(zipper, PinStripe.WebhookController) do
          {:ok, zipper} ->
            {:ok, Igniter.Code.Common.add_code(zipper, handler_code)}

          _ ->
            {:ok, zipper}
        end
      end)
    end

    defp add_module_handler(igniter, module, event, handler_module_name) do
      handler_code = ~s"""

      handle "#{event}", #{inspect(handler_module_name)}
      """

      Igniter.Project.Module.find_and_update_module!(igniter, module, fn zipper ->
        case Igniter.Code.Module.move_to_use(zipper, PinStripe.WebhookController) do
          {:ok, zipper} ->
            {:ok, Igniter.Code.Common.add_code(zipper, handler_code)}

          _ ->
            {:ok, zipper}
        end
      end)
    end

    defp create_handler_module(igniter, module, event) do
      Igniter.Project.Module.create_module(igniter, module, """
      @moduledoc \"\"\"
      Handler for #{event} Stripe webhook event.
      \"\"\"

      @doc \"\"\"
      Handles the #{event} event.
      \"\"\"
      def handle_event(event) do
        # Handle #{event} event
        :ok
      end
      """)
    end
  end
else
  defmodule Mix.Tasks.PinStripe.Gen.Handler do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'pin_stripe.gen.handler' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
