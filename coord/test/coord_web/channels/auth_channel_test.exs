defmodule CoordWeb.AuthChannelTest do
  use ExUnit.Case, async: true

  import Phoenix.ChannelTest

  @endpoint CoordWeb.Endpoint

  alias CoordWeb.AuthChannel

  test "joining without an email provides a browser sign-in URL" do
    socket_id = CoordWeb.UserSocket.auth_topic("browser-sign-in-test")
    socket = %Phoenix.Socket{id: socket_id, topic: "auth"}

    assert {:ok, %{authorization_url: authorization_url, expires_in_ms: 600_000}, joined_socket} =
             AuthChannel.join("auth", %{}, socket)

    uri = URI.parse(authorization_url)
    assert uri.path == "/auth/user/login"
    assert URI.decode_query(uri.query)["socket_id"] == socket_id

    Process.cancel_timer(joined_socket.assigns.auth_timeout_ref)
  end

  test "join rejects an invalid topic or a missing socket identity" do
    assert {:error, %{reason: "invalid_auth_topic"}} =
             AuthChannel.join("other", %{}, %Phoenix.Socket{id: "auth:unused"})

    assert {:error, %{reason: "socket_id_required"}} =
             AuthChannel.join("auth", %{}, %Phoenix.Socket{id: nil})
  end

  test "authenticated broadcast sends the device token over the channel" do
    socket_id = "auth:device-session-test"
    timeout_ref = Process.send_after(self(), :auth_timeout, :timer.minutes(1))

    socket = %Phoenix.Socket{
      assigns: %{auth_completed?: false, auth_timeout_ref: timeout_ref},
      id: socket_id,
      join_ref: "1",
      joined: true,
      serializer: Phoenix.Socket.V2.JSONSerializer,
      topic: "auth",
      transport_pid: self()
    }

    broadcast = %Phoenix.Socket.Broadcast{
      topic: socket_id,
      event: "authenticated",
      payload: %{user_id: "user-123", device_token: "opaque-device-token"}
    }

    assert {:noreply, next_socket} = AuthChannel.handle_info(broadcast, socket)
    assert Process.read_timer(timeout_ref) == false

    assert_receive {:socket_push, :text, payload}

    assert ["1", nil, "auth", "authenticated", %{"device_token" => "opaque-device-token"}] =
             payload |> IO.iodata_to_binary() |> Jason.decode!()

    assert {:noreply, ^next_socket} = AuthChannel.handle_info(broadcast, next_socket)
    refute_receive {:socket_push, :text, _payload}
  end

  test "missing device token closes the channel and cancels its timer" do
    socket_id = "auth:missing-device-token-test"

    socket =
      socket(CoordWeb.UserSocket, socket_id, %{})
      |> subscribe_and_join!(AuthChannel, "auth", %{})

    ref = Process.monitor(socket.channel_pid)

    CoordWeb.Endpoint.broadcast(socket_id, "authenticated", %{
      user_id: "user-123",
      device_token: nil
    })

    assert_push "auth_error", %{reason: "missing_session"}
    assert_receive {:DOWN, ^ref, :process, _, :normal}
    assert Process.read_timer(socket.assigns.auth_timeout_ref) == false
  end

  test "auth failure forwards its payload before closing the channel" do
    socket_id = "auth:failed-sign-in-test"

    socket =
      socket(CoordWeb.UserSocket, socket_id, %{})
      |> subscribe_and_join!(AuthChannel, "auth", %{})

    ref = Process.monitor(socket.channel_pid)

    CoordWeb.Endpoint.broadcast(socket_id, "auth_error", %{reason: "link_expired"})

    assert_push "auth_error", %{reason: "link_expired"}
    assert_receive {:DOWN, ^ref, :process, _, :normal}
    assert Process.read_timer(socket.assigns.auth_timeout_ref) == false
  end
end
