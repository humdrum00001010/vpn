defmodule Coord.Accounts do
  use Ash.Domain,
    otp_app: :coord

  resources do
    resource Coord.Accounts.Token
    resource Coord.Accounts.User
  end
end
