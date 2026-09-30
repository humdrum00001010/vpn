defmodule CoordInterface.Application do
  use Application

  @impl true
  # later should get back to here then think about this abstraction, currently it should just work for further dev / testing of core vpn
  def start(_type, _args) do
    mode =
      :coord_interface
      |> Application.fetch_env!(__MODULE__)
      |> Keyword.fetch!(:mode)

    case mode do
      :cli ->
        System.halt(CoordInterface.CLI.main(Burrito.Util.Args.argv()))

      _ ->
        Supervisor.start_link([], strategy: :one_for_one, name: CoordInterface.Supervisor)
    end
  end
end
