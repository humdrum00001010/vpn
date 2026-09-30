defmodule CoordWeb.MagicLinkController do
  use CoordWeb, :controller

  plug :put_no_store_headers

  def new(conn, %{"socket_id" => nil}) do
    conn
    |> put_status(:bad_request)
    |> render(:incomplete_request, page_title: "Could not sign in")
  end

  def new(conn, %{"socket_id" => _socket_id} = params) do
    conn
    |> render(:new, form: Phoenix.Component.to_form(params, as: :auth), page_title: "Sign in")
  end

  def new(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> render(:incomplete_request, page_title: "Could not sign in")
  end

  def request(conn, %{"auth" => %{"email" => email, "socket_id" => socket_id}})
      when is_nil(email) or is_nil(socket_id) do
    conn
    |> put_status(:bad_request)
    |> render(:incomplete_request, page_title: "Could not sign in")
  end

  def request(conn, %{"auth" => %{"email" => email, "socket_id" => socket_id}}) do
    case Coord.Accounts.request_magic_link(email,
           context: %{
             private: %{ash_authentication?: true},
             shared: %{auth_socket_id: socket_id}
           }
         ) do
      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:send_failed, page_title: "Could not send sign-in link")

      :ok ->
        render(conn, :check_email, page_title: "Check your email")
    end
  end

  def request(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> render(:incomplete_request, page_title: "Could not sign in")
  end

  def confirm(conn, %{"token" => token, "socket_id" => socket_id})
      when is_nil(token) or is_nil(socket_id) do
    conn
    |> put_status(:bad_request)
    |> render(:incomplete_confirmation, page_title: "Could not confirm sign-in")
  end

  def confirm(conn, %{"token" => _token, "socket_id" => _socket_id} = params) do
    conn
    |> render(
      :confirm,
      form: Phoenix.Component.to_form(params, as: :auth),
      page_title: "Confirm sign-in"
    )
  end

  def confirm(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> render(:incomplete_confirmation, page_title: "Could not confirm sign-in")
  end

  def complete(conn, %{"auth" => %{"token" => token, "socket_id" => socket_id}})
      when is_nil(token) or is_nil(socket_id) do
    conn
    |> put_status(:bad_request)
    |> render(:incomplete_link, page_title: "Could not sign in")
  end

  def complete(conn, %{"auth" => %{"token" => token, "socket_id" => socket_id}}) do
    case Coord.Accounts.sign_in_with_magic_link(token,
           context: %{private: %{ash_authentication?: true}}
         ) do
      {:error, _reason} ->
        CoordWeb.Endpoint.broadcast(socket_id, "auth_error", %{
          message: "This sign-in link is invalid or expired. Start again."
        })

        conn
        |> put_status(:unprocessable_entity)
        |> render(:invalid_link, page_title: "Could not sign in")

      {:ok, user} ->
        {:ok, sessions} = Coord.Accounts.create_user_sessions(user.id, socket_id)
        conn = CoordWeb.UserAuth.log_in_user(conn, sessions.browser_token)

        CoordWeb.Endpoint.broadcast(socket_id, "authenticated", %{
          user_id: user.id,
          device_token: sessions.device_token
        })

        render(conn, :submitted, page_title: "Sign-in submitted")
    end
  end

  def complete(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> render(:incomplete_link, page_title: "Could not sign in")
  end

  defp put_no_store_headers(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
  end
end
