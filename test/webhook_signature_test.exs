defmodule TinyElixirStripe.WebhookSignatureTest do
  use ExUnit.Case, async: true

  alias TinyElixirStripe.WebhookSignature

  @secret "whsec_test_secret_key"
  @payload ~s({"id":"evt_test","type":"customer.created"})

  describe "sign/3" do
    test "creates a valid signature with timestamp and hash" do
      timestamp = System.system_time(:second)
      signature = WebhookSignature.sign(@payload, timestamp, @secret)

      assert signature =~ ~r/^t=\d+,v1=[a-f0-9]{64}$/
      assert String.starts_with?(signature, "t=#{timestamp},v1=")
    end

    test "creates consistent signatures for same inputs" do
      timestamp = 1_234_567_890
      signature1 = WebhookSignature.sign(@payload, timestamp, @secret)
      signature2 = WebhookSignature.sign(@payload, timestamp, @secret)

      assert signature1 == signature2
    end

    test "creates different signatures for different payloads" do
      timestamp = System.system_time(:second)
      signature1 = WebhookSignature.sign(@payload, timestamp, @secret)
      signature2 = WebhookSignature.sign("different payload", timestamp, @secret)

      assert signature1 != signature2
    end
  end

  describe "verify/3" do
    test "accepts valid signature" do
      timestamp = System.system_time(:second)
      signature = WebhookSignature.sign(@payload, timestamp, @secret)

      assert :ok = WebhookSignature.verify(@payload, signature, @secret)
    end

    test "rejects expired signatures" do
      # Create signature 301 seconds in the past (beyond 5 minute window)
      timestamp = System.system_time(:second) - 301
      signature = WebhookSignature.sign(@payload, timestamp, @secret)

      assert {:error, "signature is expired"} =
               WebhookSignature.verify(@payload, signature, @secret)
    end

    test "rejects signatures with incorrect secret" do
      timestamp = System.system_time(:second)
      signature = WebhookSignature.sign(@payload, timestamp, @secret)

      assert {:error, "signature is incorrect"} =
               WebhookSignature.verify(@payload, signature, "wrong_secret")
    end

    test "rejects signatures with modified payload" do
      timestamp = System.system_time(:second)
      signature = WebhookSignature.sign(@payload, timestamp, @secret)
      modified_payload = ~s({"id":"evt_test","type":"customer.deleted"})

      assert {:error, "signature is incorrect"} =
               WebhookSignature.verify(modified_payload, signature, @secret)
    end

    test "rejects malformed signature header - no v1 schema" do
      signature = "t=1234567890"

      assert {:error, error} = WebhookSignature.verify(@payload, signature, @secret)
      assert error =~ "wrong format"
    end

    test "rejects malformed signature header - no timestamp" do
      signature = "v1=abcdef1234567890"

      assert {:error, error} = WebhookSignature.verify(@payload, signature, @secret)
      assert error =~ "wrong format"
    end

    test "rejects completely invalid signature format" do
      signature = "invalid"

      assert {:error, error} = WebhookSignature.verify(@payload, signature, @secret)
      assert error =~ "wrong format"
    end

    test "accepts signature at exactly 5 minutes old" do
      # Exactly 300 seconds old should still be valid
      timestamp = System.system_time(:second) - 300
      signature = WebhookSignature.sign(@payload, timestamp, @secret)

      assert :ok = WebhookSignature.verify(@payload, signature, @secret)
    end

    test "handles empty payload" do
      timestamp = System.system_time(:second)
      payload = ""
      signature = WebhookSignature.sign(payload, timestamp, @secret)

      assert :ok = WebhookSignature.verify(payload, signature, @secret)
    end

    test "handles payload with special characters" do
      timestamp = System.system_time(:second)
      payload = ~s({"data":"test with unicode: 你好, emoji: 🎉, quotes: \\"escaped\\""})
      signature = WebhookSignature.sign(payload, timestamp, @secret)

      assert :ok = WebhookSignature.verify(payload, signature, @secret)
    end

    test "rejects signature with invalid timestamp format" do
      hash = :crypto.hash(:sha256, "test") |> Base.encode16(case: :lower)
      signature = "t=invalid,v1=#{hash}"

      assert {:error, error} = WebhookSignature.verify(@payload, signature, @secret)
      assert error =~ "wrong format"
    end
  end
end
