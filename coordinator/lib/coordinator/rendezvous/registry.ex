defmodule Coordinator.Rendezvous.Registry do
  @moduledoc false

  use GenServer

  @table :coordinator_rendezvous_registry

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def upsert(room, client_id, ip, port) when is_binary(room) and is_binary(client_id) do
    GenServer.call(__MODULE__, {:upsert, room, client_id, ip, port})
  end

  def lookup(room, client_id) when is_binary(room) and is_binary(client_id) do
    case :ets.lookup(@table, {room, client_id}) do
      [{{^room, ^client_id}, endpoint}] -> {:ok, endpoint}
      [] -> :error
    end
  end

  @impl true
  def init(_state) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:upsert, room, client_id, ip, port}, _from, state) do
    endpoint = %{ip: ip, port: port, updated_at_unix: System.system_time(:second)}
    true = :ets.insert(@table, {{room, client_id}, endpoint})
    {:reply, endpoint, state}
  end
end
