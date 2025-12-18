defmodule TinyElixirStripe.ParsersWithRawBody do
  @moduledoc """
  A custom Plug.Parsers that caches the raw request body for webhook routes.

  This plug conditionally caches the raw body only for webhook endpoints
  (default: /webhooks/stripe). For all other routes, it behaves like standard
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
      plug TinyElixirStripe.ParsersWithRawBody,
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        json_decoder: Phoenix.json_library()

  The raw body will be available in `conn.assigns.raw_body` as a list of
  binary chunks for webhook routes.

  ## Configuration

  The default webhook path is `["webhooks", "stripe"]` which matches the URL
  path `/webhooks/stripe`. This will be configurable via Igniter in future versions.
  """

  @behaviour Plug

  @webhook_path ["webhooks", "stripe"]

  @doc false
  def init(opts) do
    cache = Plug.Parsers.init([body_reader: {__MODULE__, :cache_raw_body, []}] ++ opts)
    nocache = Plug.Parsers.init(opts)
    {cache, nocache}
  end

  @doc false
  def call(%{path_info: @webhook_path} = conn, {cache, _nocache}) do
    Plug.Parsers.call(conn, cache)
  end

  def call(conn, {_cache, nocache}) do
    Plug.Parsers.call(conn, nocache)
  end

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
