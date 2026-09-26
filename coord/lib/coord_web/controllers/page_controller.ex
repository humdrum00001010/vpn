defmodule CoordWeb.PageController do
  use CoordWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
