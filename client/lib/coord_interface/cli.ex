defmodule CoordInterface.CLI do
  @moduledoc """
  Command entry point for the Burrito client.
  """

  use Cheer.Command

  about("Sign in to Coord from your terminal")

  subcommand(CoordInterface.CLI.Login)

  def main(args) do
    case Cheer.run(__MODULE__, args, prog: "coord") do
      {:error, :usage} -> 2
      :ok -> 0
      _ -> 1
    end
  end
end
