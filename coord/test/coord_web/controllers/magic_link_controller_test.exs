defmodule CoordWeb.MagicLinkControllerTest do
  use CoordWeb.ConnCase

  import Swoosh.TestAssertions

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias Coord.Accounts.User

  test "browser sign-in form requests the magic link", %{conn: conn} do
    socket_id = CoordWeb.UserSocket.auth_topic("browser-form-test")

    conn = get(conn, ~p"/auth/user/login?#{[socket_id: socket_id]}")

    form =
      conn |> html_response(200) |> LazyHTML.from_document() |> LazyHTML.query("#cli-login-form")

    assert LazyHTML.attribute(form, "action") == ["/auth/user/login"]

    assert form
           |> LazyHTML.query(~s(input[name="auth[socket_id]"]))
           |> LazyHTML.attribute("value") == [socket_id]

    assert get_resp_header(conn, "cache-control") == ["no-store"]

    conn =
      conn
      |> recycle()
      |> post(~p"/auth/user/login", %{
        "auth" => %{"email" => "browser-form@example.com", "socket_id" => socket_id}
      })

    html_response(conn, 200)

    assert_email_sent(fn email ->
      assert email.to == [{"", "browser-form@example.com"}]
      assert email.html_body =~ URI.encode_www_form(socket_id)
      true
    end)
  end

  test "browser sign-in requires a socket ID", %{conn: conn} do
    conn = get(conn, ~p"/auth/user/login")
    html_response(conn, 400)
    refute_email_sent()
  end

  test "browser sign-in rejects an incomplete form", %{conn: conn} do
    conn = post(conn, ~p"/auth/user/login", %{"auth" => %{"email" => "only@example.com"}})
    html_response(conn, 400)
    refute_email_sent()
  end

  test "GET preserves confirmation fields without signing in", %{conn: conn} do
    socket_id = CoordWeb.UserSocket.auth_topic("confirm-test-socket")
    strategy = Info.strategy!(User, :magic_link)

    assert {:ok, token} =
             MagicLink.request_token_for_identity(strategy, "callback@example.com")

    conn = get(conn, ~p"/auth/user/magic_link?#{[token: token, socket_id: socket_id]}")

    form =
      conn
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("#magic-link-confirm-form")

    assert LazyHTML.attribute(form, "action") == ["/auth/user/magic_link"]
    assert LazyHTML.attribute(form, "method") == ["post"]

    assert form |> LazyHTML.query(~s(input[name="auth[token]"])) |> LazyHTML.attribute("value") ==
             [token]

    assert form
           |> LazyHTML.query(~s(input[name="auth[socket_id]"]))
           |> LazyHTML.attribute("value") == [socket_id]

    assert get_session(conn, :user_token) == nil
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
  end

  test "confirmation authenticates the CLI and persists a revocable browser session", %{
    conn: conn
  } do
    socket_id = CoordWeb.UserSocket.auth_topic("callback-test-socket")
    :ok = Phoenix.PubSub.subscribe(Coord.PubSub, socket_id)
    strategy = Info.strategy!(User, :magic_link)

    assert {:ok, token} =
             MagicLink.request_token_for_identity(strategy, "callback@example.com")

    conn =
      post(conn, ~p"/auth/user/magic_link", %{
        "auth" => %{"token" => token, "socket_id" => socket_id}
      })

    html_response(conn, 200)

    assert_receive %Phoenix.Socket.Broadcast{
      topic: ^socket_id,
      event: "authenticated",
      payload: %{user_id: user_id, device_token: device_token}
    }

    assert is_binary(device_token)
    session_token = get_session(conn, :user_token)

    assert Enum.any?(get_resp_header(conn, "set-cookie"), fn cookie ->
             String.starts_with?(cookie, "_coord_key=")
           end)

    conn = conn |> recycle() |> get(~p"/")
    assert %User{id: ^user_id} = conn.assigns.current_user
    assert to_string(conn.assigns.current_user.email) == "callback@example.com"

    assert :ok = Coord.Accounts.delete_user_session_token(session_token)

    conn = conn |> recycle() |> get(~p"/")
    assert conn.assigns.current_user == nil
    assert get_session(conn, :user_token) == nil
  end

  test "invalid magic link renders an error page and broadcasts an auth error", %{conn: conn} do
    socket_id = CoordWeb.UserSocket.auth_topic("callback-failure-socket")
    :ok = Phoenix.PubSub.subscribe(Coord.PubSub, socket_id)

    conn =
      post(conn, ~p"/auth/user/magic_link", %{
        "auth" => %{"token" => "not-a-valid-magic-link-token", "socket_id" => socket_id}
      })

    html_response(conn, 422)
    assert get_session(conn, :user_token) == nil

    assert_receive %Phoenix.Socket.Broadcast{
      topic: ^socket_id,
      event: "auth_error",
      payload: %{message: _message}
    }
  end

  test "incomplete confirmation links render an error page", %{conn: conn} do
    conn = get(conn, ~p"/auth/user/magic_link")

    html_response(conn, 400)
    assert get_session(conn, :user_token) == nil
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "incomplete confirmation submissions render an error page", %{conn: conn} do
    conn = post(conn, ~p"/auth/user/magic_link", %{"auth" => %{"token" => "only"}})
    html_response(conn, 400)
    assert get_session(conn, :user_token) == nil
  end
end
