defmodule Chroxy do
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
    chrome_ports = Keyword.get(args, :chrome_remote_debug_ports, 9222..9227)
    init_chrome_procs(chrome_ports)
    {:ok, %{}}
  end

  def handle_call(:connection, _from, state) do
    proxy_websocket = init_connection()
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
  # Proxy Connection

  @doc """
  Starts chrome process and returns ws:// address to chrome process via proxy.
  """
  def init_connection() do
    # Proxy host and port info from configuration
    proxy_opts = Application.get_env(:chroxy, Chroxy.ProxyListener)
    proxy_host = Keyword.get(proxy_opts, :host)
    proxy_port = Keyword.get(proxy_opts, :port)
    # Obtain chrome process, initialise a page, get ws:// addr
    chrome = get_chrome_server(:random)
    :ready = Chroxy.ChromeServer.ready(chrome)
    page = Chroxy.ChromeServer.new_page(chrome)
    websocket = page["webSocketDebuggerUrl"]
    uri = URI.parse(websocket)
    # Accept next connection and init proxy
    Chroxy.ProxyListener.accept(hook: Chroxy.ChromeProxy,
                                downstream_host: uri.host |> String.to_charlist,
                                downstream_port: uri.port)
    # Change gost and port in websocket address to that of the proxy
    websocket
    |> String.replace(Integer.to_string(uri.port), Integer.to_string(proxy_port))
    |> String.replace(uri.host, proxy_host)
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
