defmodule HAP.EncryptedHTTPServer do
  @moduledoc false
  # Defines the HTTP interface for a HomeKit Accessory which may only be accessed over a secure channel

  use Plug.Router

  plug(:match)
  plug(:require_authenticated_session, builder_opts())
  plug(:dispatch, builder_opts())

  def init(opts) do
    opts
  end

  post "/pairings" do
    pair_state = HAP.HAPSessionTransport.get_pair_state()

    HAP.Pairings.handle_message(conn.body_params, pair_state)
    |> case do
      {:ok, response} ->
        conn
        |> put_resp_header("content-type", "application/pairing+tlv8")
        |> send_resp(200, HAP.TLVEncoder.to_binary(response))

      {:error, reason} ->
        conn
        |> send_resp(400, reason)
    end
  end

  get "/accessories" do
    response = HAP.AccessoryServerManager.get_accessories()

    conn
    |> put_resp_header("content-type", "application/hap+json")
    |> send_resp(200, Jason.encode!(response))
  end

  get "/characteristics" do
    characteristics =
      conn.params["id"]
      |> String.split(",")
      |> Enum.map(&String.split(&1, "."))
      |> Enum.map(fn [aid, iid] -> %{aid: String.to_integer(aid), iid: String.to_integer(iid)} end)
      |> HAP.AccessoryServerManager.get_characteristics()

    if Enum.all?(characteristics, fn %{status: status} -> status == 0 end) do
      characteristics = characteristics |> Enum.map(fn characteristic -> characteristic |> Map.delete(:status) end)

      conn
      |> put_resp_header("content-type", "application/hap+json")
      |> send_resp(200, Jason.encode!(%{characteristics: characteristics}))
    else
      conn
      |> put_resp_header("content-type", "application/hap+json")
      |> send_resp(207, Jason.encode!(%{characteristics: characteristics}))
    end
  end

  put "/characteristics" do
    characteristics =
      conn.body_params["characteristics"]
      |> HAP.AccessoryServerManager.put_characteristics()

    if Enum.all?(characteristics, fn %{status: status} -> status == 0 end) do
      conn
      |> put_resp_header("content-type", "application/hap+json")
      |> send_resp(204, "")
    else
      conn
      |> put_resp_header("content-type", "application/hap+json")
      |> send_resp(207, Jason.encode!(%{characteristics: characteristics}))
    end
  end

  defp require_authenticated_session(conn, _opts) do
    if HAP.HAPSessionTransport.encrypted_session?() do
      conn
    else
      conn
      |> send_resp(401, "Not Authorized")
      |> halt()
    end
  end
end
