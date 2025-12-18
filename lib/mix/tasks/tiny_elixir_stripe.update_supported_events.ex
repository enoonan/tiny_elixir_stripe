defmodule Mix.Tasks.TinyElixirStripe.UpdateSupportedEvents do
  @shortdoc "Update the list of supported Stripe webhook events (for library contributors)"

  @moduledoc """
  Updates the list of supported Stripe webhook events.

  This task is for library contributors to update the list of valid Stripe events
  that can be used with the webhook handler generators.

  ## Usage

      mix tiny_elixir_stripe.update_supported_events

  This task will:
  1. Run `stripe trigger --help` to get the list of supported events
  2. Parse the output to extract event names
  3. Write the events to priv/supported_stripe_events.txt

  ## Requirements

  You must have the Stripe CLI installed and available in your PATH.
  Install it from: https://stripe.com/docs/stripe-cli
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("Fetching supported Stripe events from Stripe CLI...")

    case System.cmd("stripe", ["trigger", "--help"], stderr_to_stdout: true) do
      {output, 0} ->
        events = parse_events(output)

        if events == [] do
          Mix.shell().error("No events found in Stripe CLI output")
          exit({:shutdown, 1})
        end

        write_events(events)
        Mix.shell().info("Successfully updated #{length(events)} supported events")

      {error, _} ->
        Mix.shell().error("""
        Failed to run 'stripe trigger --help'. Error:
        #{error}

        Make sure you have the Stripe CLI installed:
        https://stripe.com/docs/stripe-cli
        """)

        exit({:shutdown, 1})
    end
  end

  defp parse_events(output) do
    output
    |> String.split("\n")
    |> Enum.drop_while(&(!String.starts_with?(&1, "Supported events:")))
    |> Enum.drop(1)
    |> Enum.take_while(&String.match?(&1, ~r/^\s+[a-z0-9_\.]+$/))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.sort()
  end

  defp write_events(events) do
    # Ensure priv directory exists
    File.mkdir_p!("priv")

    # Write one event per line
    content = Enum.join(events, "\n") <> "\n"
    File.write!("priv/supported_stripe_events.txt", content)
  end
end
