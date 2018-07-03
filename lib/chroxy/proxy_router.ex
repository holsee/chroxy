defmodule Chroxy.ProxyRouter do
  @moduledoc """
  Maps connection metadata (such as page_id in case of Chrome) in order
  to route incoming request to the correct browser process.
  Will monitor browser processes and automatically remove regsitrations
  if a browser process dies during the course of operation.
  """

  use GenServer

  require Logger

  @type key() :: String.t()

  @tbl __MODULE__

  @doc """
  Child specification for supervision.
  """
  @spec child_spec() :: Supervisor.child_spec()
  def child_spec() do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  @doc """
  Start new ProxyRouter registered with name `#{__MODULE__}`
  """
  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc false
  def init(_) do
    opts = [:protected, :set, :named_table,
            read_concurrency: true, write_concurrency: true]
    :ets.new(@tbl, opts)
    {:ok, %{table: @tbl}}
  end

  @doc """
  Store browser process against `key` and monitor
  """
  @spec put(key(), pid()) :: :ok
  def put(key, proc) do
    GenServer.cast(__MODULE__, {:put, key, proc})
  end

  @doc """
  Get browser process registered with `key`
  """
  @spec get(key()) :: pid()
  def get(key) do
    case :ets.lookup(@tbl, key) do
      [] -> nil
      [{_, browser,_}|_] -> browser
    end
  end

  @doc """
  Delete entry with key and demonitor.
  """
  @spec delete(key()) :: :ok
  def delete(key) do
    GenServer.cast(__MODULE__, {:delete, key})
  end

  @doc false
  def handle_cast({:put, key, proc}, state) do
    Logger.debug(fn -> "put object with key: #{key} - value: #{inspect(proc)}" end)
    ref = Process.monitor(proc)
    :ets.insert(@tbl, {key, proc, ref})
    {:noreply, state}
  end

  @doc false
  def handle_cast({:delete, key}, state) do
    Logger.debug(fn -> "deleting object with key: #{key}" end)
    case :ets.lookup(@tbl, key) do
      [] ->
        :not_found
      [{_key, _pid, ref}|_] ->
        :ets.delete(@tbl, key)
        Process.demonitor(ref)
    end

    {:noreply, state}
  end

  @doc false
  def handle_info({:DOWN, ref, :process, _object, _reason}, state) do
    Logger.debug(fn -> "received DOWN message for: #{inspect(ref)}" end)
    # Delete all the registrations for process which has went down, as the
    # lookups would no longer be valid after process dies.
    @tbl
    |> :ets.match_object({:_, :_, ref})
    |> Enum.map(fn ob -> :ets.delete_object(@tbl, ob) end)
    {:noreply, state}
  end

end

