defmodule CoordinatorWeb.HealthController do
  use CoordinatorWeb, :controller

  def show(conn, _params) do
    json(conn, %{ok: true})
  end
end
