defmodule Coordinator.Rendezvous.UdpServer do
  @moduledoc false

  use GenServer

  alias Coordinator.Rendezvous.Registry

  @port 3478

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    {:ok, socket} =
      :gen_udp.open(@port, [
        :binary,
        active: true,
        reuseaddr: true,
        ip: {0, 0, 0, 0}
      ])

    {:ok, %{socket: socket}}
  end

  @impl true
  def handle_info({:udp, socket, ip, port, data}, state) do
    _ = socket

    with {:ok, %{"room" => room, "client_id" => client_id}} <- Jason.decode(data) do
      endpoint = Registry.upsert(room, client_id, ip, port)
      udp = format_udp(endpoint)

      CoordinatorWeb.Endpoint.broadcast("rendezvous:" <> room, "udp_seen", %{
        "client_id" => client_id,
        "udp" => udp
      })

      :gen_udp.send(socket, ip, port, udp)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp format_udp(%{ip: ip, port: port}) do
    "#{:inet.ntoa(ip) |> to_string()}:#{port}"
  end
end
