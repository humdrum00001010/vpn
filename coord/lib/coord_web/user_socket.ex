defmodule CoordWeb.UserSocket do
  use Phoenix.Socket

  channel "auth", CoordWeb.AuthChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    socket_id = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    {:ok, assign(socket, :auth_socket_id, socket_id)}
  end

  @impl true
  def id(socket), do: auth_topic(socket.assigns.auth_socket_id)

  def auth_topic(socket_id), do: "auth:#{socket_id}"
end
