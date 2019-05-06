defmodule WebPushEncryption.Push do
  @moduledoc """
  Module to send web push notifications with a payload through GCM
  """

  alias WebPushEncryption.Vapid

  @fcm_url "https://fcm.googleapis.com/fcm/send"
  @temp_fcm_url "https://fcm.googleapis.com/fcm"

  @doc """
  Sends a web push notification with a payload through GCM.

  ## Arguments

    * `message` is a binary payload. It can be JSON encoded
    * `subscription` is the subscription information received from the client.
       It should have the following form: `%{keys: %{auth: AUTH, p256dh: P256DH}, endpoint: ENDPOINT}`
    * `auth_token` [Optional] is the GCM api key matching the `gcm_sender_id` from the client `manifest.json`.
       It is not necessary for Mozilla endpoints.

  ## Return value

  Returns the result of `HTTPoison.post`
  """
  @spec send_web_push(message :: binary, subscription :: map, auth_token :: binary | nil) ::
          {:ok, any} | {:error, atom}
  def send_web_push(message, subscription, auth_token \\ nil)

  def send_web_push(_message, %{endpoint: @fcm_url <> _registration_id}, nil) do
    raise ArgumentError, "send_web_push requires an auth_token for gcm endpoints"
  end

  def send_web_push(message, %{endpoint: endpoint} = subscription, auth_token) do
    payload = WebPushEncryption.Encrypt.encrypt(message, subscription)

    headers =
      Vapid.get_headers(make_audience(endpoint), "aesgcm")
      |> Map.merge(%{
        "TTL" => "0",
        "Content-Encoding" => "aesgcm",
        "Encryption" => "salt=#{ub64(payload.salt)}"
      })

    headers =
      headers
      |> Map.put("Crypto-Key", "dh=#{ub64(payload.server_public_key)};" <> headers["Crypto-Key"])

    {endpoint, headers} = make_request_params(endpoint, headers, auth_token)
    http_client().post(endpoint, payload.ciphertext, headers)
  end

  def send_web_push(_message, _subscription, _auth_token) do
    raise ArgumentError,
          "send_web_push expects a subscription endpoint with an endpoint parameter"
  end

  defp make_request_params(endpoint, headers, auth_token) do
    if fcm_url?(endpoint) do
      {make_gcm_endpoint(endpoint), headers |> Map.merge(gcm_authorization(auth_token))}
    else
      {endpoint, headers}
    end
  end

  defp make_audience(endpoint) do
    parsed = URI.parse(endpoint)
    parsed.scheme <> "://" <> parsed.host
  end

  defp fcm_url?(url), do: String.contains?(url, @fcm_url)
  defp make_gcm_endpoint(endpoint), do: String.replace(endpoint, @fcm_url, @temp_fcm_url)
  defp gcm_authorization(auth_token), do: %{"Authorization" => "key=#{auth_token}"}

  defp ub64(value) do
    Base.url_encode64(value, padding: false)
  end

  defp http_client() do
    Application.get_env(:web_push_encryption, :http_client, HTTPoison)
  end
end
