defmodule CoordWeb.UserAuth do
  import Phoenix.Controller, only: [delete_csrf_token: 0]
  import Plug.Conn

  alias Coord.Accounts

  def init(opts), do: opts

  def call(conn, :fetch_current_user), do: fetch_current_user(conn)

  def fetch_current_user(conn) do
    token = get_session(conn, :user_token)

    user = if token, do: Accounts.get_user_by_session_token!(token)

    conn =
      case {token, user} do
        {token, nil} when token != nil -> delete_session(conn, :user_token)
        _ -> conn
      end

    assign(conn, :current_user, user)
  end

  def log_in_user(conn, token) when is_binary(token) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(:user_token, token)
  end
end
