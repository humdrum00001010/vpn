defmodule CoordWeb.PageController do
  use CoordWeb, :controller

  def home(conn, _params) do
    render(conn, :home, page_title: "Device sign-in")
  end
end
