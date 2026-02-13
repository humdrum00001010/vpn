defmodule Coordinator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CoordinatorWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:coordinator, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Coordinator.PubSub},
      CoordinatorWeb.Presence,
      Coordinator.Rendezvous.Registry,
      Coordinator.Rendezvous.UdpServer,
      # Start a worker by calling: Coordinator.Worker.start_link(arg)
      # {Coordinator.Worker, arg},
      # Start to serve requests, typically the last entry
      CoordinatorWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Coordinator.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CoordinatorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
