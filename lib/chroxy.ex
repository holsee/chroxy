defmodule Chroxy do
  use GenServer

  require Logger

  # PLAN
  # ====

  # [DONE]

  # on init, take arguments that will create a pool of Chrome Process
  # -- don't hold the state here for the Chrome processes
  # -- make it do this is the ChromeServer application, and more chrome

  # instances means more deployments of this server, these could be load
  # balanced.
  # -- the only API Call needed is in fact the one we have to ask for the ws://
  # endpoint, for which we return the proxied version with the page websocket as
  # the downstread connection arguments trapped as a closure :D.

  # From this pool of processes, select one and create a page from it
  # -- balancing the connections / pages between the processes in the pool

  # [TODO]

  # Next work on the proxy to automatically close the pages when the client
  # disconnections or goes idles. The ChromeProxy / ProxyServer should have
  # a new interface to allow for dynamic configuration of the callbacks.

  # SHIP IT!

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
    chrome = get_chrome_server()
    :ready = Chroxy.ChromeServer.ready(chrome)
    page = Chroxy.ChromeServer.new_page(chrome)
    websocket = page["webSocketDebuggerUrl"]
    proxy_websocket = initialise_proxy(websocket)
    {:reply, proxy_websocket, state}
  end

  def handle_cast({:start_chrome, port}, state) do
    {:ok, _} = Chroxy.ChromeServer.Supervisor.start_child(chrome_port: port)
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
  def get_chrome_server() do
    chrome_procs = Chroxy.ChromeServer.Supervisor.which_children()
    random_server = chrome_procs |> Enum.take_random(1) |> List.first()
    Logger.info("Selected chrome server: #{inspect(random_server)}")
    elem(random_server, 1)
  end

  @proxy_port 1331

  def initialise_proxy(websocket) do
    websocket_uri = URI.parse(websocket)
    browser_host = websocket_uri.host |> String.to_charlist
    browser_port = websocket_uri.port
    # Signals proxy to accept a single connection,
    # once connection from client is established to the chrome host:port,
    # data from client will be forwarded and received by the chrome websocket,
    # and data returned will be forwarded back to the client (transparently).
    Chroxy.ProxyListener.accept(hook: Chroxy.ChromeProxy,
                                downstream_host: browser_host,
                                downstream_port: browser_port)

    proxy_websocket_addr = route_ws_via_proxy(websocket, @proxy_port)
    Logger.info("Proxy websocket: #{proxy_websocket_addr}")
    proxy_websocket_addr
  end

  @doc """
  Garbage websocket uri conversion to proxy.
  TODO We need to use real host names / ip addresses.
  """
  defp route_ws_via_proxy(websocket, proxy_port) do
    uri = URI.parse(websocket)
    String.replace(websocket,
                   Integer.to_string(uri.port),
                   Integer.to_string(proxy_port))
  end
end
