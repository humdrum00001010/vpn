defmodule Coord.Accounts.MagicLinkTest do
  use Coord.DataCase

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias Coord.Accounts.{User, UserSession}

  test "browser session tokens are opaque, persisted, and revocable" do
    strategy = Info.strategy!(User, :magic_link)

    assert {:ok, magic_link_token} =
             MagicLink.request_token_for_identity(strategy, "session@example.com")

    assert {:ok, user} =
             Coord.Accounts.sign_in_with_magic_link(magic_link_token,
               context: %{private: %{ash_authentication?: true}}
             )

    token = Coord.Accounts.generate_user_session_token!(user.id)

    assert is_binary(token)
    assert byte_size(token) == 32
    refute token == user.id
    assert %User{id: user_id} = Coord.Accounts.get_user_by_session_token!(token)
    assert user_id == user.id

    assert :ok = Coord.Accounts.delete_user_session_token(token)
    assert Coord.Accounts.get_user_by_session_token!(token) == nil
  end

  test "browser and device session keys are separate and device revocation leaves browser signed in" do
    strategy = Info.strategy!(User, :magic_link)

    assert {:ok, magic_link_token} =
             MagicLink.request_token_for_identity(strategy, "separate-sessions@example.com")

    assert {:ok, user} =
             Coord.Accounts.sign_in_with_magic_link(magic_link_token,
               context: %{private: %{ash_authentication?: true}}
             )

    socket_id = CoordWeb.UserSocket.auth_topic("separate-session-test")
    :ok = Phoenix.PubSub.subscribe(Coord.PubSub, socket_id)

    assert {:ok, %{browser_token: browser_token, device_token: device_token}} =
             Coord.Accounts.create_user_sessions(user.id, socket_id)

    assert is_binary(browser_token)
    assert byte_size(browser_token) == 32
    assert is_binary(device_token)

    assert {:ok, device_token_bytes} = Base.url_decode64(device_token, padding: false)
    assert byte_size(device_token_bytes) == 32
    refute device_token_bytes == browser_token

    assert [%UserSession{socket_id: ^socket_id} = device_session] =
             Coord.Accounts.list_user_device_sessions!(user.id)

    assert device_session.token == :crypto.hash(:sha256, device_token_bytes)
    assert Coord.Accounts.get_user_by_session_token!(device_session.token) == nil
    assert Coord.Accounts.get_user_by_session_token!(browser_token).id == user.id

    assert :ok = Coord.Accounts.revoke_user_device_session(user.id, device_session.id)

    assert_receive %Phoenix.Socket.Broadcast{
      topic: ^socket_id,
      event: "disconnect",
      payload: %{}
    }

    assert Coord.Accounts.get_user_by_session_token!(browser_token).id == user.id
    assert Coord.Accounts.list_user_device_sessions!(user.id) == []
  end
end
