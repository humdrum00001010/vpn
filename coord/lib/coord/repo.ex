defmodule Coord.Repo do
  use Ecto.Repo,
    otp_app: :coord,
    adapter: Ecto.Adapters.Postgres
end
