defmodule Coord.Accounts.User.Senders.SendMagicLinkEmail do
  @moduledoc """
  Sends a magic link email
  """

  use AshAuthentication.Sender
  use CoordWeb, :verified_routes

  import Swoosh.Email
  alias Coord.Mailer

  @impl true
  def send(user_or_email, token, opts) do
    # if you get a user, its for a user that already exists.
    # if you get an email, then the user does not yet exist.

    email =
      case user_or_email do
        %{email: email} -> email
        email -> email
      end

    socket_id = get_in(opts, [:source_context, :shared, :auth_socket_id])

    if is_nil(socket_id) do
      raise "missing auth socket id in Ash source context"
    end

    link = url(~p"/auth/user/magic_link?#{[token: token, socket_id: socket_id]}")

    escaped_email =
      email |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    escaped_link = link |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    new()
    # TODO: Replace with your email
    |> from({"noreply", "noreply@example.com"})
    |> to(to_string(email))
    |> subject("Your login link")
    |> html_body(body(link: escaped_link, email: escaped_email))
    |> Mailer.deliver!()
  end

  defp body(params) do
    """
    <p>Hello, #{params[:email]}! Confirm this sign-in request:</p>
    <p><a href="#{params[:link]}">Confirm sign-in</a></p>
    """
  end
end
