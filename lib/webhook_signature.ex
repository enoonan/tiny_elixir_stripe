defmodule TinyElixirStripe.WebhookSignature do
  @moduledoc """
  Verifies Stripe webhook signatures.

  Stripe signs webhook events and includes the signature in the `stripe-signature`
  header. This module verifies that signature to ensure the webhook came from Stripe.

  See: https://docs.stripe.com/webhooks#verify-official-libraries

  ## Configuration

  Configure your webhook secret in your application config:

      config :tiny_elixir_stripe,
        stripe_webhook_secret: "whsec_..."

  ## Usage

      payload = ~s({"id": "evt_test", "type": "customer.created"})
      signature = get_req_header(conn, "stripe-signature")
      secret = Application.fetch_env!(:tiny_elixir_stripe, :stripe_webhook_secret)

      case WebhookSignature.verify(payload, signature, secret) do
        :ok ->
          # Process webhook
        {:error, reason} ->
          # Reject webhook
      end
  """

  @schema "v1"
  @valid_period_in_seconds 300

  @doc """
  Signs payload with timestamp and secret.

  Useful for testing webhook handling.

  ## Examples

      iex> payload = ~s({"type": "test"})
      iex> timestamp = System.system_time(:second)
      iex> secret = "whsec_test"
      iex> signature = TinyElixirStripe.WebhookSignature.sign(payload, timestamp, secret)
      iex> String.starts_with?(signature, "t=")
      true
  """
  @spec sign(binary(), integer(), binary()) :: binary()
  def sign(payload, timestamp, secret) do
    signature = "#{@schema}=" <> hash(timestamp, payload, secret)
    "t=#{timestamp}," <> signature
  end

  @doc """
  Verifies payload against signature and secret.

  Returns `:ok` if the signature is valid and not expired.
  Returns `{:error, reason}` otherwise.

  The signature must be less than 300 seconds (5 minutes) old to prevent
  replay attacks.

  ## Examples

      iex> payload = ~s({"type": "test"})
      iex> timestamp = System.system_time(:second)
      iex> secret = "whsec_test"
      iex> signature = TinyElixirStripe.WebhookSignature.sign(payload, timestamp, secret)
      iex> TinyElixirStripe.WebhookSignature.verify(payload, signature, secret)
      :ok
  """
  @spec verify(binary(), binary(), binary()) :: :ok | {:error, binary()}
  def verify(payload, signature, secret) do
    with {:ok, timestamp, hash} <- parse(signature, @schema) do
      current_timestamp = System.system_time(:second)

      cond do
        timestamp + @valid_period_in_seconds < current_timestamp ->
          {:error, "signature is expired"}

        not Plug.Crypto.secure_compare(hash, hash(timestamp, payload, secret)) ->
          {:error, "signature is incorrect"}

        true ->
          :ok
      end
    end
  end

  defp parse(signature, schema) do
    parsed =
      for pair <- String.split(signature, ","),
          destructure([key, value], String.split(pair, "=", parts: 2)),
          do: {key, value},
          into: %{}

    with %{"t" => timestamp, ^schema => hash} <- parsed,
         {timestamp, ""} <- Integer.parse(timestamp) do
      {:ok, timestamp, hash}
    else
      _ -> {:error, "signature is in a wrong format or is missing #{schema} schema"}
    end
  end

  defp hash(timestamp, payload, secret) do
    :crypto.mac(:hmac, :sha256, secret, ["#{timestamp}.", payload])
    |> Base.encode16(case: :lower)
  end
end
