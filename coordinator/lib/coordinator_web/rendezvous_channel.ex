defmodule CoordinatorWeb.RendezvousChannel do
  @moduledoc false

  use CoordinatorWeb, :channel

  alias Coordinator.Rendezvous.Registry
  alias CoordinatorWeb.Presence

  @impl true
  def join("rendezvous:" <> room, %{"client_id" => client_id}, socket)
      when is_binary(room) and is_binary(client_id) do
    socket =
      socket
      |> assign(:room, room)
      |> assign(:client_id, client_id)

    send(self(), :after_join)
    {:ok, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    room = socket.assigns.room
    client_id = socket.assigns.client_id
    topic = "rendezvous:" <> room

    meta =
      case Registry.lookup(room, client_id) do
        {:ok, endpoint} ->
          %{"udp" => "#{:inet.ntoa(endpoint.ip) |> to_string()}:#{endpoint.port}"}

        :error ->
          %{}
      end

    {:ok, _} = Presence.track(socket, client_id, meta)
    push(socket, "presence_state", Presence.list(topic))
    {:noreply, socket}
  end
end
