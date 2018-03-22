defmodule Chroxy do
  use GenServer

  require Logger


  # PLAN
  # ====
  #
  # on init, take arguments that will create a pool of Chrome Process
  # -- don't hold the state here for the Chrome processes
  # -- make it do this is the ChromeServer application, and more chrome
  # instances means more deployments of this server, these could be load
  # balanced.
  # -- the only API Call needed is in fact the one we have to ask for the ws://
  # endpoint, for which we return the proxied version with the page websocket as
  # the downstread connection arguments trapped as a closure :D.
  # ---> Ultimately we will need to look at Chroxy.ChromeProxy definition, it
  # may need moved here.  Also we may want to have another hook on termination,
  # not just on establishing the connection.
  #
  # From this pool of processes, select one and create a page from it
  # -- balancing the connections / pages between the processes in the pool
  #
  # Next work on the proxy to automatically close the pages when the client
  # disconnections or goes idles. The ChromeProxy / ProxyServer should have
  # a new interface to allow for dynamic configuration of the callbacks.
  #
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

  def start_chrome(port) do
    # TODO This is likely to become a Start Chromes, and delagate all state to the
    # Chrome Supervisor.  This process is not to be stateful it if can be
    # helped!
    GenServer.call(__MODULE__, {:start_chrome, port})
  end

  def connection(chrome) when is_pid(chrome) do
    GenServer.call(__MODULE__, {:connection, chrome})
  end

  ##
  # Callbacks

  def init(_args) do
    {:ok, %{}}
  end

  def handle_call({:connection, chrome}, _from, state) do
    :ready = Chroxy.ChromeServer.ready(chrome)
    page = Chroxy.ChromeServer.new_page(chrome)
    websocket = page["webSocketDebuggerUrl"]
    # TODO We have all the info here needed to populate the initialisation
    # closure for the proxy connection
    {:reply, websocket, state}
  end

  def handle_call({:start_chrome, port}, _from, state) do
    {:ok, pid} = Chroxy.ChromeServer.Supervisor.start_child(chrome_port: port)
    # TODO Monitor Chrome process
    {:reply, pid, Map.put(state, :chrome, pid)}
  end

end

