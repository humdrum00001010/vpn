defmodule CoordInterface.MixProject do
  use Mix.Project

  def project do
    [
      app: :coord_interface,
      version: "0.1.0",
      elixir: "1.20.4",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  def application do
    [
      mod: {CoordInterface.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:burrito, "~> 1.6"},
      {:phoenix_gen_socket_client, "~> 3.3.0", hex: :phx_gen_socket_client},
      {:websocket_client, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:owl, "~> 0.13"},
      {:cheer, "~> 0.2.2"}
    ]
  end

  defp releases do
    [
      coord_interface: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            macos: [os: :darwin, cpu: :aarch64],
            macos_intel: [os: :darwin, cpu: :x86_64],
            linux: [os: :linux, cpu: :x86_64],
            windows: [os: :windows, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end
end
