defmodule CoordWeb.AuthChannel do
  use CoordWeb, :channel
  use CoordWeb, :verified_routes

  @impl true
  def join(topic, _params, _socket) when topic != "auth",
    do: {:error, %{reason: "invalid_auth_topic"}}

  def join("auth", _params, %{id: nil}),
    do: {:error, %{reason: "socket_id_required"}}

  def join("auth", _params, %{id: socket_id} = socket) do
    timeout_ms =
      :coord
      |> Application.fetch_env!(__MODULE__)
      |> Keyword.fetch!(:timeout_ms)

    :ok = Phoenix.PubSub.subscribe(Coord.PubSub, socket.id)
    timeout_ref = Process.send_after(self(), :auth_timeout, timeout_ms)

    socket =
      assign(socket,
        auth_completed?: false,
        authenticated_user_id: nil,
        auth_timeout_ref: timeout_ref
      )

    {:ok,
     %{
       authorization_url: url(~p"/auth/user/login?#{[socket_id: socket_id]}"),
       expires_in_ms: timeout_ms
     }, socket}
  end

  def join("auth", _params, _socket), do: {:error, %{reason: "socket_id_required"}}

  @impl true
  def handle_info(:auth_timeout, socket) do
    push(socket, "auth_expired", %{message: "Sign-in expired. Start again."})
    {:stop, :normal, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: socket_id,
          event: "auth_error",
          payload: payload
        },
        %{id: socket_id} = socket
      ) do
    if socket.assigns.auth_completed? do
      {:noreply, socket}
    else
      push(socket, "auth_error", payload)
      Process.cancel_timer(socket.assigns.auth_timeout_ref)
      {:stop, :normal, socket}
    end
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: socket_id,
          event: "authenticated",
          payload: %{user_id: user_id, device_token: device_token}
        },
        %{id: socket_id} = socket
      )
      when is_nil(user_id) or is_nil(device_token) do
    if socket.assigns.auth_completed? do
      {:noreply, socket}
    else
      push(socket, "auth_error", %{reason: "missing_session"})
      Process.cancel_timer(socket.assigns.auth_timeout_ref)
      {:stop, :normal, socket}
    end
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: socket_id,
          event: "authenticated",
          payload: %{user_id: user_id, device_token: device_token}
        },
        %{id: socket_id} = socket
      ) do
    if socket.assigns.auth_completed? do
      {:noreply, socket}
    else
      Process.cancel_timer(socket.assigns.auth_timeout_ref)

      push(socket, "authenticated", %{device_token: device_token})

      {:noreply,
       socket
       |> assign(:authenticated_user_id, user_id)
       |> assign(:auth_completed?, true)}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
