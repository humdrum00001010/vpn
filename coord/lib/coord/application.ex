defmodule Coord.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CoordWeb.Telemetry,
      Coord.Repo,
      {DNSCluster, query: Application.get_env(:coord, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Coord.PubSub},
      # Start a worker by calling: Coord.Worker.start_link(arg)
      # {Coord.Worker, arg},
      # Start to serve requests, typically the last entry
      CoordWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Coord.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CoordWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
