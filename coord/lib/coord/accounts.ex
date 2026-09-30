defmodule Coord.Accounts do
  use Ash.Domain,
    otp_app: :coord

  alias Coord.Accounts.UserSession

  resources do
    resource Coord.Accounts.Token

    resource Coord.Accounts.User do
      define :request_magic_link,
        action: :request_magic_link,
        args: [:email],
        default_options: [context: %{private: %{ash_authentication?: true}}]

      define :sign_in_with_magic_link,
        action: :sign_in_with_magic_link,
        args: [:token],
        default_options: [context: %{private: %{ash_authentication?: true}}]

      define :get_user_by_session_token,
        action: :by_session_token,
        args: [:token],
        get?: true,
        not_found_error?: false
    end

    resource UserSession do
      define :create_browser_session_record, action: :browser, args: [:user_id, :token]

      define :create_device_session_record,
        action: :device,
        args: [:user_id, :token, :socket_id]

      define :browser_session_by_token,
        action: :browser_by_token,
        args: [:token],
        get?: true,
        not_found_error?: false

      define :list_user_device_sessions, action: :devices_for_user, args: [:user_id]

      define :device_session_for_user,
        action: :device_for_user,
        args: [:id, :user_id],
        get?: true,
        not_found_error?: false

      define :generate_user_session_token, action: :issue_browser_token, args: [:user_id]
      define :create_user_sessions, action: :issue_sessions, args: [:user_id, :socket_id]
      define :delete_user_session_token, action: :delete_browser_session, args: [:token]

      define :revoke_user_device_session,
        action: :revoke_device_session,
        args: [:user_id, :session_id]
    end
  end
end
