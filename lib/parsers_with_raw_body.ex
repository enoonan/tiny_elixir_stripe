defmodule PinStripe.ParsersWithRawBody do
  @moduledoc """
  A custom Plug.Parsers that caches the raw request body for webhook routes.

  This plug conditionally caches the raw body only for webhook endpoints
  configured in your application. For all other routes, it behaves like standard
  Plug.Parsers.

  The raw body is needed for webhook signature verification, as the signature
  is computed over the exact bytes received from Stripe.

  ## Usage

  In your Phoenix endpoint, replace `Plug.Parsers` with this module:

      # Before:
      plug Plug.Parsers,
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        json_decoder: Phoenix.json_library()

      # After:
      plug PinStripe.ParsersWithRawBody,
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        json_decoder: Phoenix.json_library()

  The raw body will be available in `conn.assigns.raw_body` as a list of
  binary chunks for webhook routes.

  ## Configuration

  Configure webhook paths in your `config/runtime.exs` as a list:

      config :pin_stripe,
        webhook_paths: ["/webhooks/stripe"]

  You can configure multiple webhook endpoints:

      config :pin_stripe,
        webhook_paths: ["/webhooks/stripe", "/webhooks/stripe_connect"]

  If no configuration is provided, the default path `["/webhooks/stripe"]` will be used.

  ## Multiple Webhook Endpoints

  To add additional webhook endpoints:

  1. Add the path to the `:webhook_paths` config (as shown above)
  2. Create a new controller that uses `PinStripe.WebhookController`:

      defmodule MyAppWeb.StripeConnectWebhookController do
        use PinStripe.WebhookController

        handle "account.updated", fn event ->
          # Handle Connect events
          :ok
        end
      end

  3. Add the route in your router:

      scope "/webhooks" do
        post "/stripe_connect", MyAppWeb.StripeConnectWebhookController, :create
      end
  """

  @behaviour Plug

  @default_webhook_path "/webhooks/stripe"

  @doc false
  def init(opts) do
    cache = Plug.Parsers.init([body_reader: {__MODULE__, :cache_raw_body, []}] ++ opts)
    nocache = Plug.Parsers.init(opts)
    {cache, nocache}
  end

  @doc false
  def call(conn, {cache, nocache}) do
    if webhook_path?(conn.path_info) do
      Plug.Parsers.call(conn, cache)
    else
      Plug.Parsers.call(conn, nocache)
    end
  end

  # Check if the current path matches any configured webhook paths
  defp webhook_path?(path_info) do
    configured_paths = get_webhook_paths()
    Enum.any?(configured_paths, fn webhook_path -> path_info == webhook_path end)
  end

  # Get configured webhook paths from application config
  defp get_webhook_paths do
    case Application.get_env(:pin_stripe, :webhook_paths) do
      nil ->
        # Default to standard webhook path
        [path_to_path_info(@default_webhook_path)]

      paths when is_list(paths) ->
        Enum.map(paths, &path_to_path_info/1)
    end
  end

  # Convert a string path like "/webhooks/stripe" to path_info format ["webhooks", "stripe"]
  defp path_to_path_info(path) when is_binary(path) do
    path
    |> String.split("/", trim: true)
  end

  # Already in path_info format
  defp path_to_path_info(path) when is_list(path), do: path

  @doc """
  Custom body reader that caches the raw request body.

  This function is passed to Plug.Parsers via the :body_reader option.
  It reads the body and stores it in conn.assigns.raw_body as a list
  of chunks (prepended for efficiency).
  """
  def cache_raw_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])
        {:ok, body, conn}

      {:more, partial, conn} ->
        conn = update_in(conn.assigns[:raw_body], &[partial | &1 || []])
        {:more, partial, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
