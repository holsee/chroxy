defmodule Chroxy.ChromeManager do
  @moduledoc """
  Starts browser processes (via `ChromeServer`)
  and provides access to connections (via `ChromeProxy`).
  """

  use GenServer

  require Logger

  @default_port_range 9222..9227

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
    chrome_ports = Keyword.get(args, :chrome_remote_debug_ports, @default_port_range)
    init_chrome_procs(chrome_ports)
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
    # Wait until it is ready
    :ready = Chroxy.ChromeServer.ready(chrome)
    # Chrome spawns with an open page, lets close it.
    :ok = Chroxy.ChromeServer.close_all_pages(chrome)
    {:noreply, state}
  end

  ##
  # Chrome Pool

  @doc """
  For each port in the port provided, spawn a chrome browser process.
  """
  def init_chrome_procs(ports) do
    ports
    |> Enum.map(&start_chrome(&1))
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
