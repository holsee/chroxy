defmodule Chroxy do
  use GenServer

  require Logger

  # PLAN
  # ====

  # [DONE]

  # on init, take arguments that will create a pool of Chrome Process
  # -- don't hold the state here for the Chrome processes
  # -- make it do this is the ChromeServer application, and more chrome

  # [TODO]

  # instances means more deployments of this server, these could be load
  # balanced.
  # -- the only API Call needed is in fact the one we have to ask for the ws://
  # endpoint, for which we return the proxied version with the page websocket as
  # the downstread connection arguments trapped as a closure :D.

  # ---> Ultimately we will need to look at Chroxy.ChromeProxy definition, it
  # may need moved here.  Also we may want to have another hook on termination,
  # not just on establishing the connection.

  # From this pool of processes, select one and create a page from it
  # -- balancing the connections / pages between the processes in the pool

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
    proxy_socket = initialise_proxy(websocket)
    {:reply, proxy_socket, state}
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

  def initialise_proxy(websocket) do
    websocket_uri = URI.parse(websocket)
    proxy_port = 1331

    {:ok, proxy_server} =
      Chroxy.ProxyServer.serve(
        1,
        :ranch_tcp,
        [port: proxy_port],
        proxy: fn data ->
          host = websocket_uri.host |> String.to_charlist()
          port = websocket_uri.port
          [remote: {host, port}, data: data, reply: ""]
        end
      )

    # Garbage websocket uri conversion to proxy
    websocket_port_s = websocket_uri.port |> Integer.to_string()
    proxy_port_s = proxy_port |> Integer.to_string()
    proxy_socket = String.replace(websocket, websocket_port_s, proxy_port_s)

    Logger.info("Proxy websocket: #{proxy_socket}")
    proxy_socket
  end
end
