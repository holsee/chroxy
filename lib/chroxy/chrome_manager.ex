defmodule Chroxy.ChromeManager do
  @moduledoc """
  Starts browser processes (via `ChromeServer`)
  and provides access to connections (via `ChromeProxy`).
  """

  use GenServer

  require Logger

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      shutdown: 5000,
      type: :worker
    }
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  ##
  # API

  @doc """
  Starts a chrome browser process
  """
  def start_chrome(port) do
    GenServer.cast(__MODULE__, {:start_chrome, port})
  end

  @doc """
  Request new page websocket url
  """
  def connection() do
    GenServer.call(__MODULE__, :connection)
  end

  ##
  # Callbacks

  def init(args) do
    Logger.warn("ARGS: #{inspect(args)}")
    Process.flag(:trap_exit, true)
    chrome_port_from = Keyword.get(args, :chrome_remote_debug_port_from) |> String.to_integer()
    chrome_port_to = Keyword.get(args, :chrome_remote_debug_port_to) |> String.to_integer()
    init_chrome_procs(Range.new(chrome_port_from, chrome_port_to))
    {:ok, %{}}
  end

  def handle_call(:connection, _from, state) do
    chrome = get_chrome_server(:random)
    {:ok, pid} = Chroxy.ChromeProxy.start_link(chrome: chrome)
    proxy_websocket = Chroxy.ChromeProxy.chrome_connection(pid)
    {:reply, proxy_websocket, state}
  end

  def handle_cast({:start_chrome, port}, state) do
    {:ok, chrome} = Chroxy.ChromeServer.Supervisor.start_child(chrome_port: port)
    # Wait for chrome to init and enter a ready state for connections...
    case Chroxy.ChromeServer.ready(chrome) do
      :ready ->
        # when ready close the pages which are openned by default
        #:ok = Chroxy.ChromeServer.close_all_pages(chrome)
        :ok
      :timeout ->
        # failed to become ready in an acceptable timeframe
        Logger.error("Failed to start chrome on port #{port}")
    end
    {:noreply, state}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    Logger.info("ChromeManager linked process #{inspect(pid)} exited with reason: #{inspect(reason)}")
    {:noreply, state}
  end

  ##
  # Chrome Pool

  @doc """
  For each port in the port provided, spawn a chrome browser process.
  """
  def init_chrome_procs(ports) do
    Enum.map(ports, &start_chrome(&1))
  end

  @doc """
  Select random chrome server from which to spawn a new page.
  """
  def get_chrome_server(:random) do
    chrome_procs = Chroxy.ChromeServer.Supervisor.which_children()
    random_server = chrome_procs |> Enum.take_random(1) |> List.first()
    Logger.info("Selected chrome server: #{inspect(random_server)}")
    elem(random_server, 1)
  end
end
