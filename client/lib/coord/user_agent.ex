defmodule Coord.UserAgent do
  @moduledoc """
  Phoenix Channels user agent for the coordinator's `auth` channel.

  The socket process owns protocol state. It opens the coordinator's sign-in
  page and waits for authentication. The socket remains the active session.
  """

  @behaviour Phoenix.Channels.GenSocketClient

  alias Phoenix.Channels.GenSocketClient
  alias Phoenix.Channels.GenSocketClient.Serializer.Json
  alias Phoenix.Channels.GenSocketClient.Transport.WebSocketClient

  @impl true
  def init(opts) do
    state = %{
      socket_url: Keyword.fetch!(opts, :socket_url),
      open_browser: Keyword.get(opts, :open_browser, true),
      waiter: nil
    }

    {:noconnect, state.socket_url, [], state}
  end

  def start_link(opts) do
    GenSocketClient.start_link(
      __MODULE__,
      WebSocketClient,
      opts,
      # haven't thought about the serializer though, I think it's fine here
      serializer: Json
    )
  end

  def authenticate(socket_url, timeout \\ :timer.minutes(10)) do
    case start_link(socket_url: socket_url) do
      {:error, reason} ->
        {:error, {:user_agent_start_failed, reason}}

      {:ok, socket} ->
        try do
          case GenSocketClient.call(socket, :session, timeout) do
            {:error, _reason} = error ->
              stop(socket)
              error

            {:ok, device_token} ->
              {:ok, socket, device_token}
          end
        catch
          :exit, {:timeout, _call} ->
            stop(socket)
            {:error, :timeout}

          :exit, reason ->
            stop(socket)
            {:error, reason}
        end
    end
  end

  @impl true
  def handle_connected(transport, state) do
    case GenSocketClient.join(transport, "auth", %{}) do
      {:error, reason} ->
        :ok = GenSocketClient.reply(state.waiter, {:error, {:join_failed, reason}})
        {:stop, :normal, %{state | waiter: nil}}

      {:ok, _ref} ->
        {:ok, state}
    end
  end

  @impl true
  def handle_joined("auth", %{"authorization_url" => url}, _transport, state) do
    Owl.IO.puts([
      Owl.Data.tag("Continue in your browser: ", [:cyan, :bright]),
      Owl.Data.tag(url, [:cyan, :underline])
    ])

    Owl.IO.puts(
      Owl.Data.tag(
        "Enter your email, then open the link in your inbox and confirm sign-in.",
        :faint
      )
    )

    Owl.IO.puts(Owl.Data.tag("Waiting for you to confirm…", :cyan))

    if state.open_browser do
      opener = browser_command(:os.type(), url)

      if opener do
        {command, args} = opener

        if System.find_executable(command) do
          Task.start(System, :cmd, [command, args, [stderr_to_stdout: true]])
        end
      end
    end

    {:ok, state}
  end

  @impl true
  def handle_join_error("auth", payload, _transport, state) do
    :ok = GenSocketClient.reply(state.waiter, {:error, {:join_rejected, payload}})
    {:stop, :normal, %{state | waiter: nil}}
  end

  @impl true
  def handle_reply(_topic, _ref, _payload, _transport, state), do: {:ok, state}

  @impl true
  def handle_message("auth", "auth_error", payload, _transport, state) do
    :ok = GenSocketClient.reply(state.waiter, {:error, {:authentication_failed, payload}})
    {:stop, :normal, %{state | waiter: nil}}
  end

  def handle_message("auth", "auth_expired", payload, _transport, state) do
    :ok = GenSocketClient.reply(state.waiter, {:error, {:authentication_expired, payload}})
    {:stop, :normal, %{state | waiter: nil}}
  end

  def handle_message("auth", "authenticated", payload, _transport, state) do
    case {device_session_token(payload), state.waiter} do
      {nil, {_pid, _ref} = waiter} ->
        :ok = GenSocketClient.reply(waiter, {:error, :device_session_token_missing})
        {:stop, :normal, %{state | waiter: nil}}

      {_, nil} ->
        {:ok, state}

      {device_token, waiter} ->
        :ok = GenSocketClient.reply(waiter, {:ok, device_token})
        {:ok, %{state | waiter: nil}}
    end
  end

  def handle_message(_topic, _event, _payload, _transport, state), do: {:ok, state}

  @impl true
  def handle_disconnected(reason, %{waiter: {_pid, _ref} = waiter} = state) do
    :ok = GenSocketClient.reply(waiter, {:error, {:disconnected, reason}})
    {:stop, :normal, %{state | waiter: nil}}
  end

  def handle_disconnected(_reason, %{waiter: nil} = state), do: {:stop, :normal, state}

  @impl true
  def handle_channel_closed(
        "auth",
        payload,
        _transport,
        %{waiter: {_pid, _ref} = waiter} = state
      ) do
    :ok = GenSocketClient.reply(waiter, {:error, {:channel_closed, payload}})
    {:stop, :normal, %{state | waiter: nil}}
  end

  def handle_channel_closed("auth", _payload, _transport, %{waiter: nil} = state),
    do: {:stop, :normal, state}

  def handle_channel_closed(_topic, _payload, _transport, state), do: {:ok, state}

  @impl true
  def handle_info(:connect, _transport, state), do: {:connect, state}

  def handle_info(_message, _transport, state), do: {:ok, state}

  @impl true
  def handle_call(:session, _from, _transport, %{waiter: {_pid, _ref}} = state) do
    {:reply, {:error, :session_already_pending}, state}
  end

  def handle_call(:session, from, _transport, %{waiter: nil} = state) do
    send(self(), :connect)
    {:noreply, %{state | waiter: from}}
  end

  def handle_call(_message, _from, _transport, state), do: {:reply, :ok, state}

  def stop(socket) do
    if Process.alive?(socket) do
      GenServer.stop(socket, :normal)
    end
  catch
    :exit, _reason -> :ok
  end

  defp browser_command({:unix, :darwin}, url), do: {"open", [url]}
  defp browser_command({:unix, :linux}, url), do: {"xdg-open", [url]}

  defp browser_command({:win32, _}, url),
    do: {"rundll32.exe", ["url.dll,FileProtocolHandler", url]}

  defp browser_command(_platform, _url), do: nil

  defp device_session_token(%{"device_token" => token}) when is_binary(token), do: token
  defp device_session_token(_payload), do: nil
end
