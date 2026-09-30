defmodule Coord.UserAgentTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Coord.UserAgent

  test "authenticated events deliver the device token to the waiting caller" do
    ref = make_ref()
    device_token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    assert {:ok, %{waiter: nil}} =
             UserAgent.handle_message(
               "auth",
               "authenticated",
               %{"device_token" => device_token},
               nil,
               state({self(), ref})
             )

    assert_receive {^ref, {:ok, ^device_token}}
  end

  test "an authenticated event without a device token stops the pending session" do
    ref = make_ref()

    assert {:stop, :normal, %{waiter: nil}} =
             UserAgent.handle_message("auth", "authenticated", %{}, nil, state({self(), ref}))

    assert_receive {^ref, {:error, :device_session_token_missing}}
  end

  test "auth errors reply to the caller and stop" do
    ref = make_ref()

    assert {:stop, :normal, %{waiter: nil}} =
             UserAgent.handle_message(
               "auth",
               "auth_error",
               %{"reason" => "expired"},
               nil,
               state({self(), ref})
             )

    assert_receive {^ref, {:error, {:authentication_failed, %{"reason" => "expired"}}}}
  end

  test "a joined channel exposes its authorization URL" do
    state = state(nil)
    url = "http://localhost:4000/auth/user/login?socket_id=auth%3Atest"

    output =
      capture_io(fn ->
        assert {:ok, ^state} =
                 UserAgent.handle_joined("auth", %{"authorization_url" => url}, nil, state)
      end)

    assert output =~ url
  end

  defp state(waiter) do
    %{
      socket_url: "ws://localhost/socket/websocket",
      open_browser: false,
      waiter: waiter
    }
  end
end
