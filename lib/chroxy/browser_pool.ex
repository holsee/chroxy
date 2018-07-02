defmodule Chroxy.BrowserPool do
  @moduledoc """
  Provides connections to Browser instances, through the
  orchestration of proxied connections to processes managing
  the OS browser processes.

  Responisble for initialisation of the pool of browsers when
  the app starts.
  """
  use GenServer

  require Logger

  defguardp is_supported(browser) when browser in [:chrome]

  def child_spec() do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      restart: :transient,
      shutdown: 5000,
      type: :worker
    }
  end

  @doc """
  Spawns #{__MODULE__} process and the browser processes.
  For each port in the range provided, an instance of chrome will
  be initialised.
  """
  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  ##
  # API

  @doc """
  Request new page websocket url.
  """
  def connection(browser) when is_supported(browser) do
    GenServer.call(__MODULE__, {:connection, browser}, 60_000)
  end

  ##
  # Callbacks

  @doc false
  def init(args) do
    Logger.warn("ARGS: #{inspect(args)}")
    Process.flag(:trap_exit, true)
    {:ok, chrome_pool} = Chroxy.BrowserPool.Chrome.start_link()
    {:ok, %{chrome_pool: chrome_pool}}
  end

  @doc false
  def handle_call({:connection, :chrome}, _from, state) do
    connection = Chroxy.BrowserPool.Chrome.get_connection()
    {:reply, connection, state}
  end

  @doc false
  def handle_info({:EXIT, pid, reason}, state) do
    Logger.info("BrowserPool link #{inspect(pid)} exited: #{inspect(reason)}")
    {:noreply, state}
  end

end

defmodule Chroxy.BrowserPool.Chrome do
  use GenServer
  require Logger

  # API

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start_browser(port) do
    GenServer.cast(__MODULE__, {:start_chrome, port})
  end

  @doc """
  Sequentially loop through processes on each call.
  Ordered access is not gauranteed as processes may crash and be restarted.
  """
  def get_browser(:next) do
    GenServer.call(__MODULE__, {:get_browser, :next})
  end

  @doc """
  Select a random browser from the pool.
  """
  def get_browser(:random) do
    pool()
    |> Enum.take_random(1)
    |> List.first()
  end

  def get_connection() do
    :next
    |> get_browser()
    |> get_connection()
  end

  def get_connection(chrome) do
    GenServer.call(__MODULE__, {:get_connection, chrome})
  end

  # Callbacks

  def init([]) do
    opts = Application.get_all_env(:chroxy)
    chrome_port_from = Keyword.get(opts, :chrome_remote_debug_port_from) |> String.to_integer()
    chrome_port_to = Keyword.get(opts, :chrome_remote_debug_port_to) |> String.to_integer()
    ports = Range.new(chrome_port_from, chrome_port_to)
    Enum.map(ports, &start_browser(&1))
    {:ok, %{browsers: [], access_count: 0}}
  end

  @doc false
  def handle_cast({:start_chrome, port}, state) do
    {:ok, chrome} = Chroxy.ChromeServer.Supervisor.start_child(chrome_port: port)

    # Wait for chrome to init and enter a ready state for connections...
    case Chroxy.ChromeServer.ready(chrome) do
      :ready ->
        # when ready close the pages which are openned by default
        # :ok = Chroxy.ChromeServer.close_all_pages(chrome)
        :ok

      :timeout ->
        # failed to become ready in an acceptable timeframe
        Logger.error("Failed to start chrome on port #{port}")
    end

    {:noreply, state}
  end

  @doc false
  def handle_call({:get_browser, :next}, _from, state = %{access_count: access_count}) do
    browsers = pool()
    idx = Integer.mod(access_count, Enum.count(browsers))
    {:reply, Enum.at(browsers, idx), %{state | access_count: access_count + 1}}
  end

  @doc false
  def handle_call({:get_connection, chrome}, _from, state) do
    {:ok, pid} = Chroxy.ChromeProxy.start_link(chrome: chrome)
    url = Chroxy.ChromeProxy.chrome_connection(pid)
    page_id = page_id({:url, url})
    IO.inspect(page_id_url: page_id)
    Chroxy.ProxyRouter.put(page_id, pid)
    {:reply, url, state}
  end

  def page_id({:url, url}) do
    url
    |> String.split("/")
    |> List.last()
  end

  def page_id({:http_request, data}) do
    data
    |> String.split(" HTTP")
    |> List.first()
    |> String.split("GET /devtools/page/")
    |> Enum.at(1)
  end

  @doc """
  List active worker processes in pool.
  """
  def pool() do
    Chroxy.ChromeServer.Supervisor.which_children()
    |> Enum.filter(fn
         ({_, p, :worker, _}) when is_pid(p) ->
           Chroxy.ChromeServer.ready(p) == :ready
         (_) -> false
       end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort()
  end

end
