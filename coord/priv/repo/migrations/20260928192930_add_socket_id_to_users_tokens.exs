defmodule Coord.Repo.Migrations.AddSocketIdToUsersTokens do
  use Ecto.Migration

  def change do
    alter table(:users_tokens) do
      add :socket_id, :string
    end
  end
end
