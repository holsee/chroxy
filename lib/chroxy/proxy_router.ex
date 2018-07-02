defmodule Chroxy.ProxyRouter do
  @moduledoc """
  Maps connection metadata (such as page_id in case of Chrome) in order
  to route incoming request to the correct browser process.
  Will monitor browser processes and automatically remove regsitrations
  if a browser process dies during the course of operation.
  """

  use GenServer

  @tbl __MODULE__

  def child_spec() do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    opts = [:public, :set, :named_table,
            read_concurrency: true, write_concurrency: true]
    :ets.new(@tbl, opts)
    {:ok, %{table: @tbl}}
  end

  def put(key, proc) do
    ref = Process.monitor(proc)
    :ets.insert(@tbl, {key, proc, ref})
  end

  def get(key) do
    case :ets.lookup(@tbl, key) do
      [] -> nil
      [{_, browser,_}|_] -> browser
    end
  end

  def handle_info({:DOWN, ref, :process, _object, _reason}, state) do
    # Delete all the registrations for process which has went down, as the
    # lookups would no longer be valid after process dies.
    @tbl
    |> :ets.match_object({:_, :_, ref})
    |> Enum.map(fn ob -> :ets.delete_object(@tbl, ob) end)
    {:noreply, state}
  end

end

