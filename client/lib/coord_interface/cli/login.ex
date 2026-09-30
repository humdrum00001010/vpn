defmodule CoordInterface.CLI.Login do
  @moduledoc false

  use Cheer.Command

  command "login" do
    about("Sign in to Coord")

    option(:socket_url,
      type: :string,
      short: :s,
      help: "Use a different Coord server (ws:// or wss://)"
    )
  end

  @impl Cheer.Command
  def run(args, _raw_argv) do
    default_socket_url =
      :coord_interface
      |> Application.fetch_env!(Coord.UserAgent)
      |> Keyword.fetch!(:socket_url)

    socket_url = Map.get(args, :socket_url) || default_socket_url

    if is_nil(socket_url) do
      Owl.IO.puts(
        Owl.Data.tag(
          "This copy of Coord has no server address. Use --socket-url to specify one.",
          :red
        )
      )

      {:error, :coordinator_not_configured}
    else
      Owl.IO.puts(Owl.Data.tag("Connecting to Coord…", :cyan))

      case Coord.UserAgent.authenticate(socket_url) do
        {:error, :timeout} = error ->
          Owl.IO.puts(Owl.Data.tag("Sign-in timed out. Run coord login to start again.", :red))

          error

        {:error, {:authentication_expired, _payload}} = error ->
          Owl.IO.puts(Owl.Data.tag("Sign-in timed out. Run coord login to start again.", :red))

          error

        {:error, {reason, _details}} = error when reason in [:disconnected, :channel_closed] ->
          Owl.IO.puts(
            Owl.Data.tag(
              "Lost connection to Coord. Check your connection and run coord login again.",
              :red
            )
          )

          error

        {:error, {:authentication_failed, _payload}} = error ->
          Owl.IO.puts(
            Owl.Data.tag(
              "Couldn't confirm sign-in. Run coord login and use the newest email link.",
              :red
            )
          )

          error

        {:error, _reason} = error ->
          Owl.IO.puts(
            Owl.Data.tag("Couldn't sign in to Coord. Run coord login to try again.", :red)
          )

          error

        {:ok, socket, _device_token} ->
          Owl.IO.puts(Owl.Data.tag("You're signed in to Coord.", [:green, :bright]))
          Owl.IO.puts(Owl.Data.tag("Keep this terminal open to stay signed in.", :faint))

          Owl.IO.input(
            label:
              Owl.Data.tag(
                ["Press ", Owl.Data.tag("Enter", :bright), " to disconnect."],
                :faint
              ),
            optional: true
          )

          Coord.UserAgent.stop(socket)
          Owl.IO.puts(Owl.Data.tag("Disconnected from Coord.", :faint))
          :ok
      end
    end
  end
end
