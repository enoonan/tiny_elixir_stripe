defmodule TinyElixirStripe.ParsersWithRawBodyTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias TinyElixirStripe.ParsersWithRawBody

  @webhook_path "/webhooks/stripe"
  @non_webhook_path "/api/customers"
  @json_payload ~s({"type":"customer.created","id":"evt_123"})

  describe "init/1" do
    test "returns tuple of cached and non-cached parser options" do
      opts = [
        parsers: [:json],
        pass: ["*/*"],
        json_decoder: Jason
      ]

      {cache, nocache} = ParsersWithRawBody.init(opts)

      assert is_tuple(cache)
      assert is_tuple(nocache)
      assert cache != nocache
    end
  end

  describe "call/2 for webhook path" do
    setup do
      opts =
        ParsersWithRawBody.init(
          parsers: [:json],
          pass: ["*/*"],
          json_decoder: Jason
        )

      {:ok, opts: opts}
    end

    test "caches raw body for webhook path", %{opts: opts} do
      conn =
        conn(:post, @webhook_path, @json_payload)
        |> put_req_header("content-type", "application/json")
        |> ParsersWithRawBody.call(opts)

      assert conn.assigns[:raw_body] != nil
      assert is_list(conn.assigns.raw_body)
      # Body chunks are prepended, so we need to reverse and concatenate
      raw_body = conn.assigns.raw_body |> Enum.reverse() |> IO.iodata_to_binary()
      assert raw_body == @json_payload
    end

    test "parses JSON body for webhook path", %{opts: opts} do
      conn =
        conn(:post, @webhook_path, @json_payload)
        |> put_req_header("content-type", "application/json")
        |> ParsersWithRawBody.call(opts)

      assert conn.body_params == %{"type" => "customer.created", "id" => "evt_123"}
    end

    test "handles empty body for webhook path", %{opts: opts} do
      conn =
        conn(:post, @webhook_path, "")
        |> put_req_header("content-type", "application/json")
        |> ParsersWithRawBody.call(opts)

      # Empty body should still create raw_body assign
      assert conn.assigns[:raw_body] != nil
    end

    test "caches raw body with special characters", %{opts: opts} do
      payload = ~s({"data":"unicode: 你好, emoji: 🎉, quotes: \\"escaped\\""})

      conn =
        conn(:post, @webhook_path, payload)
        |> put_req_header("content-type", "application/json")
        |> ParsersWithRawBody.call(opts)

      raw_body = conn.assigns.raw_body |> Enum.reverse() |> IO.iodata_to_binary()
      assert raw_body == payload
    end
  end

  describe "call/2 for non-webhook paths" do
    setup do
      opts =
        ParsersWithRawBody.init(
          parsers: [:json],
          pass: ["*/*"],
          json_decoder: Jason
        )

      {:ok, opts: opts}
    end

    test "does not cache raw body for non-webhook path", %{opts: opts} do
      conn =
        conn(:post, @non_webhook_path, @json_payload)
        |> put_req_header("content-type", "application/json")
        |> ParsersWithRawBody.call(opts)

      assert conn.assigns[:raw_body] == nil
    end

    test "still parses JSON body for non-webhook path", %{opts: opts} do
      conn =
        conn(:post, @non_webhook_path, @json_payload)
        |> put_req_header("content-type", "application/json")
        |> ParsersWithRawBody.call(opts)

      assert conn.body_params == %{"type" => "customer.created", "id" => "evt_123"}
    end

    test "does not cache for GET requests", %{opts: opts} do
      conn =
        conn(:get, @non_webhook_path)
        |> ParsersWithRawBody.call(opts)

      assert conn.assigns[:raw_body] == nil
    end

    test "does not cache for root path", %{opts: opts} do
      conn =
        conn(:post, "/", @json_payload)
        |> put_req_header("content-type", "application/json")
        |> ParsersWithRawBody.call(opts)

      assert conn.assigns[:raw_body] == nil
    end
  end

  describe "cache_raw_body/2" do
    test "stores body chunk in conn.assigns.raw_body" do
      conn = conn(:post, @webhook_path, @json_payload)

      {:ok, body, updated_conn} = ParsersWithRawBody.cache_raw_body(conn, length: 1_000_000)

      assert body == @json_payload
      assert updated_conn.assigns.raw_body == [@json_payload]
    end

    test "prepends chunks to raw_body list" do
      conn = conn(:post, @webhook_path, @json_payload)

      # First read
      {:ok, chunk1, conn} = ParsersWithRawBody.cache_raw_body(conn, length: 1_000_000)

      # Verify chunk is stored
      assert conn.assigns.raw_body == [chunk1]

      # Manually add another chunk to simulate multiple reads
      conn = update_in(conn.assigns[:raw_body], &["second_chunk" | &1])

      # Verify chunks are prepended (newest first)
      assert conn.assigns.raw_body == ["second_chunk", chunk1]
      assert length(conn.assigns.raw_body) == 2
    end

    test "initializes raw_body assign if not present" do
      conn = conn(:post, @webhook_path, @json_payload)
      refute Map.has_key?(conn.assigns, :raw_body)

      {:ok, _body, updated_conn} = ParsersWithRawBody.cache_raw_body(conn, length: 1_000_000)

      assert Map.has_key?(updated_conn.assigns, :raw_body)
    end
  end
end
