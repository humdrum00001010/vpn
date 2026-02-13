defmodule CoordinatorWeb.Presence do
  @moduledoc false

  use Phoenix.Presence,
    otp_app: :coordinator,
    pubsub_server: Coordinator.PubSub
end
