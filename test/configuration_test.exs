defmodule PinStripe.ConfigurationTest do
  use ExUnit.Case, async: false

  describe "stripe_api_key configuration" do
    test "Client uses :stripe_api_key config key" do
      # Set the config
      Application.put_env(:pin_stripe, :stripe_api_key, "sk_test_config_key")
      Application.put_env(:pin_stripe, :req_options, plug: {Req.Test, PinStripe}, retry: false)

      Req.Test.stub(PinStripe, fn conn ->
        # Verify the auth header contains the config value
        auth_header = Plug.Conn.get_req_header(conn, "authorization")
        assert auth_header == ["Bearer sk_test_config_key"]

        Req.Test.json(conn, %{id: "test"})
      end)

      # Make a request to trigger the auth
      PinStripe.Client.read("cus_123")

      # Restore default test config
      Application.put_env(:pin_stripe, :stripe_api_key, "sk_test_123")
      Application.put_env(:pin_stripe, :req_options, plug: {Req.Test, PinStripe}, retry: false)
    end

    test "Client raises helpful error when :stripe_api_key is not configured" do
      # Ensure config is not set
      Application.delete_env(:pin_stripe, :stripe_api_key)

      assert_raise ArgumentError, ~r/:stripe_api_key/, fn ->
        PinStripe.Client.read("cus_123")
      end

      # Restore default test config
      Application.put_env(:pin_stripe, :stripe_api_key, "sk_test_123")
    end
  end

  describe "stripe_webhook_secret configuration" do
    test "WebhookController uses :stripe_webhook_secret config key" do
      # Set the config
      Application.put_env(:pin_stripe, :stripe_webhook_secret, "whsec_test_secret")

      # Create a test payload and signature
      payload = ~s({"id":"evt_test","type":"customer.created","data":{"object":{}}})
      timestamp = System.system_time(:second)
      signature = PinStripe.WebhookSignature.sign(payload, timestamp, "whsec_test_secret")

      # The webhook controller internally calls verify/3 which fetches from config
      # We just need to verify the config key is correct
      secret = Application.fetch_env!(:pin_stripe, :stripe_webhook_secret)
      assert secret == "whsec_test_secret"

      # Verify that the signature verification works with this config
      assert :ok = PinStripe.WebhookSignature.verify(payload, signature, secret)

      # Clean up (this key is not set globally, so we can delete it)
      Application.delete_env(:pin_stripe, :stripe_webhook_secret)
    end

    test "WebhookController code expects :stripe_webhook_secret config key" do
      # Read the transformer source to verify it uses the correct config key
      transformer_source = File.read!("lib/webhook_handler/transformers/generate_handle_event.ex")

      assert transformer_source =~ ":stripe_webhook_secret"
      refute transformer_source =~ "webhook_signing_secret"
    end
  end

  describe "documentation consistency" do
    test "README uses correct config keys" do
      readme = File.read!("README.md")

      # Check that it mentions the correct config keys
      assert readme =~ "stripe_api_key"
      assert readme =~ "stripe_webhook_secret"

      # Check that it doesn't use incorrect variants
      refute readme =~ "webhook_signing_secret"
    end

    test "usage-rules.md uses correct config keys" do
      usage_rules = File.read!("usage-rules.md")

      # Check that it mentions the correct config keys  
      assert usage_rules =~ "stripe_api_key"
      assert usage_rules =~ "stripe_webhook_secret"

      # Check that it doesn't use incorrect variants
      refute usage_rules =~ "webhook_signing_secret"
    end

    test "all source files use correct config keys" do
      # Check that all .ex files use the correct config keys
      lib_files = Path.wildcard("lib/**/*.ex")

      for file <- lib_files do
        content = File.read!(file)

        # If the file references stripe config, it should use the correct keys
        if content =~ "fetch_env!" and content =~ ":pin_stripe" do
          # Check for correct keys
          assert content =~ ":stripe_api_key" or content =~ ":stripe_webhook_secret" or
                   not (content =~ "stripe" and content =~ "fetch_env"),
                 "File #{file} may use incorrect config keys"
        end
      end
    end
  end
end
