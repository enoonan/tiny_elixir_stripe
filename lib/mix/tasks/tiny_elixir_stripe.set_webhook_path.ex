defmodule Mix.Tasks.TinyElixirStripe.SetWebhookPath.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc do
    "Update the webhook endpoint path for TinyElixirStripe"
  end

  @spec example() :: String.t()
  def example do
    "mix tiny_elixir_stripe.set_webhook_path /new/webhook/path"
  end

  @spec long_doc() :: String.t()
  def long_doc do
    """
    #{short_doc()}

    This task updates the webhook route in your Phoenix router to use a new path.
    It will find the existing StripeWebhookController route and update
    it to the new path you specify.

    ## Example

    ```sh
    #{example()}
    ```

    ## Arguments

    * `path` - The new webhook path (e.g., "/webhooks/stripe" or "/api/stripe-webhook")
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.TinyElixirStripe.SetWebhookPath do
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
        positional: [:path],
        composes: [],
        schema: [],
        defaults: [],
        aliases: [],
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      new_path = igniter.args.positional[:path]

      unless new_path do
        raise ArgumentError, """
        webhook path is required. 

        Usage: mix tiny_elixir_stripe.set_webhook_path /new/path

        Example: mix tiny_elixir_stripe.set_webhook_path /webhooks/stripe
        """
      end

      igniter
      |> add_new_webhook_route(new_path)
      |> Igniter.add_notice("""
      New webhook route added at #{new_path}.

      Please manually review your router and remove any old StripeWebhookController routes
      if they exist to avoid duplicate route handling.
      """)
    end

    defp add_new_webhook_route(igniter, webhook_path) do
      {igniter, router} = Igniter.Libs.Phoenix.select_router(igniter)

      if router do
        # Get the generated controller module
        web_module = Igniter.Libs.Phoenix.web_module(igniter)
        controller_module = Module.concat([web_module, "StripeWebhookController"])

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
          "Could not find a Phoenix router. Please manually add the webhook route."
        )
      end
    end
  end
else
  defmodule Mix.Tasks.TinyElixirStripe.SetWebhookPath do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'tiny_elixir_stripe.set_webhook_path' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
