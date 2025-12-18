defmodule Mix.Tasks.TinyElixirStripe.Install.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc do
    "Install TinyElixirStripe with Stripe webhook support"
  end

  @spec example() :: String.t()
  def example do
    "mix tiny_elixir_stripe.install --path /webhooks/stripe"
  end

  @spec long_doc() :: String.t()
  def long_doc do
    """
    #{short_doc()}

    This installer will:

    1. Replace Plug.Parsers with TinyElixirStripe.ParsersWithRawBody in your Phoenix endpoint
    2. Create a stub WebhookHandler module in lib/{app} for defining event handlers
    3. Generate a StripeWebhookController in lib/{app}_web that uses TinyElixirStripe.WebhookController
    4. Add a webhook route to your router that points to the generated controller
    5. Add :tiny_elixir_stripe to import_deps in .formatter.exs for DSL formatting support

    The ParsersWithRawBody plug caches the raw request body for webhook signature verification,
    as required by Stripe's webhook security.

    The generated controller automatically handles signature verification and forwards events
    to your WebhookHandler module.

    ## Example

    ```sh
    #{example()}
    ```

    ## Options

    * `--path` or `-p` - The webhook endpoint path (default: "/webhooks/stripe")
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.TinyElixirStripe.Install do
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
        composes: [],
        schema: [path: :string],
        defaults: [path: "/webhooks/stripe"],
        aliases: [p: :path],
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      webhook_path = igniter.args.options[:path]

      igniter
      |> replace_plug_parsers()
      |> create_webhook_handler_stub()
      |> create_webhook_controller()
      |> add_webhook_route(webhook_path)
      |> add_formatter_config()
    end

    # Replace Plug.Parsers with TinyElixirStripe.ParsersWithRawBody in the Phoenix endpoint
    defp replace_plug_parsers(igniter) do
      {igniter, endpoint} = Igniter.Libs.Phoenix.select_endpoint(igniter)

      if endpoint do
        update_endpoint_plug_parsers(igniter, endpoint)
      else
        add_endpoint_warning(igniter)
      end
    end

    defp add_endpoint_warning(igniter) do
      Igniter.add_warning(
        igniter,
        "Could not find a Phoenix endpoint to modify. Please manually replace Plug.Parsers with TinyElixirStripe.ParsersWithRawBody."
      )
    end

    defp update_endpoint_plug_parsers(igniter, endpoint) do
      case Igniter.Project.Module.find_and_update_module(
             igniter,
             endpoint,
             &replace_plug_parsers_in_module/1
           ) do
        {:ok, igniter} -> igniter
        {:error, igniter} -> igniter
      end
    end

    defp replace_plug_parsers_in_module(zipper) do
      with {:ok, zipper} <- find_plug_parsers_call(zipper),
           {:ok, zipper} <- replace_with_parsers_with_raw_body(zipper) do
        {:ok, zipper}
      else
        _ ->
          # If we can't find Plug.Parsers, that's OK - the user might not have one
          # or might have already replaced it
          {:ok, zipper}
      end
    end

    defp find_plug_parsers_call(zipper) do
      Igniter.Code.Function.move_to_function_call(zipper, :plug, 2, &plug_parsers?/1)
    end

    defp plug_parsers?(call_zipper) do
      case Sourceror.Zipper.node(call_zipper) do
        {:plug, _, [{:__aliases__, _, [:Plug, :Parsers]} | _]} -> true
        _ -> false
      end
    end

    defp replace_with_parsers_with_raw_body(zipper) do
      Igniter.Code.Function.update_nth_argument(zipper, 0, fn arg_zipper ->
        new_module = {:__aliases__, [alias: false], [:TinyElixirStripe, :ParsersWithRawBody]}
        {:ok, Sourceror.Zipper.replace(arg_zipper, new_module)}
      end)
    end

    # Add formatter configuration to import TinyElixirStripe DSL formatting rules
    defp add_formatter_config(igniter) do
      Igniter.Project.Formatter.import_dep(igniter, :tiny_elixir_stripe)
    end

    # Create a webhook controller in lib/{app}_web/controllers
    defp create_webhook_controller(igniter) do
      # Get the handler module that was created or found
      {igniter, handler_module} = get_or_create_handler_module(igniter)

      # Determine the controller module name
      web_module = Igniter.Libs.Phoenix.web_module(igniter)
      controller_module = Module.concat([web_module, "StripeWebhookController"])

      # Create the controller
      Igniter.Project.Module.create_module(igniter, controller_module, """
      use TinyElixirStripe.WebhookController, 
        handler: #{inspect(handler_module)}
      """)
    end

    # Get or create the handler module and return it
    defp get_or_create_handler_module(igniter) do
      case find_existing_webhook_handler(igniter) do
        {igniter, nil} ->
          # No existing handler found, create a new one
          module_name =
            Module.concat([
              Igniter.Project.Module.module_name_prefix(igniter),
              "StripeWebhookHandlers"
            ])

          igniter =
            Igniter.Project.Module.create_module(igniter, module_name, """
            use TinyElixirStripe.WebhookHandler
            """)

          {igniter, module_name}

        {igniter, existing_module} ->
          # Module already exists, return it
          {igniter, existing_module}
      end
    end

    # Create a stub WebhookHandler module in lib/{app}
    defp create_webhook_handler_stub(igniter) do
      {igniter, _module} = get_or_create_handler_module(igniter)
      igniter
    end

    defp find_existing_webhook_handler(igniter) do
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

    # Add the webhook route to the router
    defp add_webhook_route(igniter, webhook_path) do
      {igniter, router} = Igniter.Libs.Phoenix.select_router(igniter)

      if router do
        # Get the generated controller module
        web_module = Igniter.Libs.Phoenix.web_module(igniter)
        controller_module = Module.concat([web_module, "StripeWebhookController"])

        # Parse the webhook path to extract scope and route parts
        # E.g., "/webhooks/stripe" -> scope: "/webhooks", route: "/stripe"
        path_parts = String.split(webhook_path, "/", trim: true)

        case path_parts do
          [] ->
            Igniter.add_warning(
              igniter,
              "Invalid webhook path provided. Please manually add the webhook route."
            )

          [single_part] ->
            # Just a single path like "/stripe", add directly to api scope
            Igniter.Libs.Phoenix.append_to_scope(
              igniter,
              "/api",
              ~s(post "/#{single_part}", #{inspect(controller_module)}, :create),
              router: router,
              with_pipelines: [:api]
            )

          parts ->
            # Multiple parts like "/webhooks/stripe"
            # Add a scope for all but the last part, then add the route for the last part
            scope_path = "/" <> Enum.join(Enum.drop(parts, -1), "/")
            route_part = List.last(parts)

            igniter
            |> Igniter.Libs.Phoenix.add_scope(
              scope_path,
              ~s(post "/#{route_part}", #{inspect(controller_module)}, :create),
              router: router,
              placement: :after
            )
        end
      else
        Igniter.add_warning(
          igniter,
          "Could not find a Phoenix router to modify. Please manually add the webhook route."
        )
      end
    end
  end
else
  defmodule Mix.Tasks.TinyElixirStripe.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'tiny_elixir_stripe.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
