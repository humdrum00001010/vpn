defmodule CoordWeb.ErrorJSONTest do
  use CoordWeb.ConnCase, async: true

  test "renders 404" do
    assert CoordWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end
end
