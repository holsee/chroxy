defmodule Chroxy.ChromeProxy do
  @moduledoc """
  Process which establishes a single proxied websocket connection
  to an underlying chrome browser page remote debugging websocket.

  Upon initialisation, the chrome proxy signal the `ProxyListener`
  to accept a TCP connection.  The `ProxyListener` will initialise a
  `ProxyServer` to manage the connection between the upstream client
  and the downstream chrome remote debugging websocket.

  When either the upstream or downstream connections close, the `down/2`
  behaviours `ProxyServer.Hook` callback is invoked, allowing the `ChromeProxy`
  to close the chrome page.
  """
  use GenServer

  require Logger

  @behaviour Chroxy.ProxyServer.Hook

  ##
  # API

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
    GenServer.start_link(__MODULE__, args)
  end

  @doc """
  Starts a chrome page, and returns a websocket connection
  routed via the underlying proxy.
  """
  def chrome_connection(ref) do
    proxy_ws = GenServer.call(ref, :chrome_connection)
    # TODO we may wish to timebomb if `up/2` is not called i.e. client
    # connection not established.  We would also want to place a timeout on the
    # accept.
    proxy_ws
  end

  ##
  # Proxy Hook Callbacks

  @doc """
  Called when upstream or downstream connections are closed.
  Will close the chrome page and shutdown this process.
  """
  def down(ref, proxy_state) do
    GenServer.cast(ref, {:down, proxy_state})
  end

  ##
  # GenServer Callbacks

  def init(args) do
    chrome_pid = Keyword.get(args, :chrome)
    # We don't need to terminate the underlying proxy if the chrome browser process
    # goes down as:
    #   1. It may not have been openned yet when client is yet to connect.
    #   2. The socket close signal when browser is terminated will terminate the proxy.
    # In the event it has not been established yet, we will want to terminate
    # this process, alas it should be linked.
    Process.link(chrome_pid)
    {:ok, %{chrome: chrome_pid, page: nil}}
  end

  def handle_call(:chrome_connection, _from, state = %{chrome: chrome, page: nil}) do
    # Create a new page
    page = Chroxy.ChromeServer.new_page(chrome)
    # Get the websocket host:port for the page and pass to the proxy listener
    # directly in order to set the downstream connection proxy process when
    # a upstream client connects. (Note: no need to use `up/2` callback as we
    # have the downstream information available at tcp listener accept time).
    uri = page["webSocketDebuggerUrl"] |> URI.parse
    Chroxy.ProxyListener.accept(
      hook: %{mod: __MODULE__, ref: self()},
      downstream_host: uri.host |> String.to_charlist(),
      downstream_port: uri.port
    )
    proxy_websocket = proxy_websocket_addr(page)
    {:reply, proxy_websocket, state = %{state|page: page}}
  end
  def handle_call(:chrome_connection, _from, state = %{page: page}) do
    proxy_websocket = proxy_websocket_addr(page)
    {:reply, proxy_websocket, state}
  end

  def handle_cast({:down, proxy_state}, state = %{chrome: chrome, page: page}) do
    Logger.info("Proxy connection down - closing page")
    # Close the page as connect is down
    Chroxy.ChromeServer.close_page(chrome, page)
    # terminate this process, as underlying proxy connections have been closed
    {:stop, :normal, state}
  end

  defp proxy_websocket_addr(%{"webSocketDebuggerUrl" => websocket}) do
    # Change host and port in websocket address to that of the proxy
    proxy_opts = Application.get_env(:chroxy, Chroxy.ProxyListener)
    proxy_host = Keyword.get(proxy_opts, :host)
    proxy_port = Keyword.get(proxy_opts, :port)
    uri = URI.parse(websocket)
    proxy_websocket = websocket
                      |> String.replace(Integer.to_string(uri.port), Integer.to_string(proxy_port))
                      |> String.replace(uri.host, proxy_host)
    proxy_websocket
  end
end
