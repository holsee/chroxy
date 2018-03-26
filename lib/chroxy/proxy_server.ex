defmodule Chroxy.ProxyListener do
  use GenServer

  require Logger

  @upstream_tcp_opts [
    :binary,
    packet: 0,
    active: true,
    port: 1331,
    backlog: 10_000,
    reuseaddr: true
  ]

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

  @doc """
  Accepts incoming tcp connections and spawns a dynamic transparent proxy
  to handle the connection.
  """
  def accept(proxy_opts) do
    GenServer.cast(__MODULE__, {:accept, proxy_opts})
  end

  ##
  # Callbacks

  def init(args) do
    send(self(), :listen)
    {:ok, %{listen_socket: nil}}
  end

  def handle_info(:listen, state = %{listen_socket: nil}) do
    case :gen_tcp.listen(0, @upstream_tcp_opts) do
      {:ok, socket} ->
        {:noreply, state = %{listen_socket: socket}}
      {:error, reason} ->
        Logger.error("TCP Listen failed due to: #{inspect(reason)}")
        {:stop, :normal, state}
    end
  end

  def handle_info(msg, state) do
    Logger.warn("[#{inspect(__MODULE__)}:#{inspect(self())}] Received message: #{inspect(msg)}}")
    {:noreply, state}
  end

  def handle_cast({:accept, proxy_opts}, state = %{listen_socket: socket}) do
    case :gen_tcp.accept(socket) do
      {:ok, upstream_socket} ->
        Logger.info("connection established, spawning proxy server for connection")
        # TODO we want a supervisor for the ProxyServers not a direct link to
        # listener
        {:ok, proxy} = Chroxy.ProxyServer.start_link(upstream_socket: upstream_socket,
                                                     proxy_opts: proxy_opts)
        # set the spawned proxy as the controlling process for the socket
        :gen_tcp.controlling_process(upstream_socket, proxy)
        {:noreply, state}
      {:error, :closed} ->
        Logger.warn("Upstream listener socket closed")
        {:stop, :normal, state}
      {:error, :timeout} ->
        Logger.error("Upstream listener timed out waiting to accept")
        {:stop, :normal, state}
      {:error, :system_limit} ->
        Logger.error("Upstream listen hit system limit all available ports in the Erlang emulator are in use")
        {:stop, :normal, state}
    end
  end

end

defmodule Chroxy.ProxyServer do
  use GenServer

  require Logger

  @downstream_tcp_opts [
    :binary,
    packet: 0,
    active: true,
    nodelay: true
  ]

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

  def init(args) do
    upstream_socket = Keyword.get(args, :upstream_socket)
    proxy_opts = Keyword.get(args, :proxy_opts)
    downstream_host = Keyword.get(proxy_opts, :downstream_host)
    downstream_port = Keyword.get(proxy_opts, :downstream_port)
    send(self(), :init_downstream)
    {:ok,
     %{
       upstream: %{
         socket: upstream_socket
       },
       downstream: %{
         host: downstream_host,
         port: downstream_port,
         tcp_opts: @downstream_tcp_opts,
         socket: nil
       }
     }}
  end

  def handle_info(:init_downstream, state = %{downstream: downstream}) do
    {:ok, down_socket} = :gen_tcp.connect(downstream.host,
                                          downstream.port,
                                          downstream.tcp_opts)
    Logger.info("Downstream connection established")
    {:noreply, %{
       state
       | downstream: %{
           downstream
           | socket: down_socket
         }
     }}
  end

  def handle_info({:tcp, downstream_socket, data}, state = %{upstream: %{socket: upstream_socket},
                                                             downstream: %{socket: downstream_socket}}) do
    Logger.info("Up <- Down: #{inspect(data)}")
    :gen_tcp.send(upstream_socket, data)
    {:noreply, state}
  end

  def handle_info({:tcp, upstream_socket, data}, state = %{upstream: %{socket: upstream_socket},
                                                           downstream: %{socket: downstream_socket}}) do
    Logger.info("Up -> Down: #{inspect(data)}")
    :gen_tcp.send(downstream_socket, data)
    {:noreply, state}
  end

  def handle_info({:tcp_closed, upstream_socket}, state = %{upstream: %{socket: upstream_socket},
                                                            downstream: %{socket: downstream_socket}}) do
    Logger.info("Upstream socket closed, terminating proxy")
    :gen_tcp.close(downstream_socket)
    :gen_tcp.close(upstream_socket)
    {:stop, :normal, state}
  end

  def handle_info({:tcp_closed, downstream_socket}, state = %{upstream: %{socket: upstream_socket},
                                                              downstream: %{socket: downstream_socket}}) do
    Logger.info("Downstream socket closed, terminating proxy")
    :gen_tcp.close(downstream_socket)
    :gen_tcp.close(upstream_socket)
    {:stop, :normal, state}
  end

  def handle_info(msg, state) do
    Logger.warn("[#{inspect(__MODULE__)}:#{inspect(self())}] Received message: #{inspect(msg)}")
    {:noreply, state}
  end

end
