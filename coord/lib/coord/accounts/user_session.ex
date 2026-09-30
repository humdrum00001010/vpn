defmodule Coord.Accounts.UserSession do
  use Ash.Resource,
    otp_app: :coord,
    domain: Coord.Accounts,
    data_layer: AshPostgres.DataLayer

  @session_token_bytes 32

  postgres do
    table "users_tokens"
    repo Coord.Repo

    references do
      reference :user do
        on_delete :delete
      end
    end

    identity_index_names context_token: "users_tokens_context_token_index"
  end

  attributes do
    uuid_primary_key :id

    attribute :token, :binary do
      allow_nil? false
      sensitive? true
    end

    attribute :context, :string do
      allow_nil? false
    end

    attribute :socket_id, :string
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :user, Coord.Accounts.User do
      allow_nil? false
    end
  end

  actions do
    defaults [:read, :destroy]

    create :browser do
      accept [:token]
      argument :user_id, :uuid, allow_nil?: false

      change set_attribute(:user_id, arg(:user_id))
      change set_attribute(:context, "session")
    end

    create :device do
      accept [:token]
      argument :user_id, :uuid, allow_nil?: false
      argument :socket_id, :string, allow_nil?: false

      change set_attribute(:user_id, arg(:user_id))
      change set_attribute(:socket_id, arg(:socket_id))
      change set_attribute(:context, "device")
    end

    read :browser_by_token do
      argument :token, :binary, allow_nil?: false, sensitive?: true
      filter expr(context == "session" and token == ^arg(:token))
    end

    read :devices_for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(context == "device" and user_id == ^arg(:user_id))
    end

    read :device_for_user do
      argument :id, :uuid, allow_nil?: false
      argument :user_id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id) and user_id == ^arg(:user_id) and context == "device")
    end

    action :issue_browser_token, :binary do
      argument :user_id, :uuid, allow_nil?: false

      run fn input, _context ->
        token = :crypto.strong_rand_bytes(@session_token_bytes)
        Coord.Accounts.create_browser_session_record!(input.arguments.user_id, token)
        {:ok, token}
      end
    end

    action :issue_sessions, :map do
      transaction? true
      argument :user_id, :uuid, allow_nil?: false
      argument :socket_id, :string, allow_nil?: false

      run fn input, _context ->
        browser_token = :crypto.strong_rand_bytes(@session_token_bytes)
        device_token = :crypto.strong_rand_bytes(@session_token_bytes)

        Coord.Accounts.create_browser_session_record!(input.arguments.user_id, browser_token)

        Coord.Accounts.create_device_session_record!(
          input.arguments.user_id,
          :crypto.hash(:sha256, device_token),
          input.arguments.socket_id
        )

        {:ok,
         %{
           browser_token: browser_token,
           device_token: Base.url_encode64(device_token, padding: false)
         }}
      end
    end

    action :delete_browser_session do
      argument :token, :binary, allow_nil?: false, sensitive?: true

      run fn input, _context ->
        case Coord.Accounts.browser_session_by_token!(input.arguments.token) do
          nil -> :ok
          session -> Ash.destroy!(session)
        end
      end
    end

    action :revoke_device_session do
      argument :user_id, :uuid, allow_nil?: false
      argument :session_id, :uuid, allow_nil?: false

      run fn input, _context ->
        case Coord.Accounts.device_session_for_user!(
               input.arguments.session_id,
               input.arguments.user_id
             ) do
          nil ->
            {:error, :not_found}

          %{socket_id: nil} ->
            {:error, :not_found}

          %{socket_id: socket_id} = session ->
            Ash.destroy!(session)
            CoordWeb.Endpoint.broadcast(socket_id, "disconnect", %{})
            :ok

          _ ->
            {:error, :not_found}
        end
      end
    end
  end

  identities do
    identity :context_token, [:context, :token]
  end
end
