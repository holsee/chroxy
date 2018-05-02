defmodule Chroxy.ProxyListener do
  @moduledoc """
  Reponsible for accepting upstream connections from client, and delegating
  ownership of the connection to a new `Chroxy.ProxyServer` process which will
  in turn create the transparent forwarding channel to the downstream host.
  """
  use GenServer

  require Logger

  @upstream_tcp_opts [
    :binary,
    packet: 0,
    active: true,
    backlog: 10_000,
    reuseaddr: true
  ]

  @default_port 1331

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      shutdown: 5000,
      type: :worker
    }
  end

  @doc """
  Spawns a ProxyLister which will listen on the port.

  Keyword `args`:
  - `:port` - port in which the TCP listener will accept connections.
  """
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc """
  Instruct listener to accept incoming tcp connections and spawn a
  dynamic transparent proxy `Chroxy.ProxySever` to handle the connection.
  """
  def accept(proxy_opts) do
    GenServer.cast(__MODULE__, {:accept, proxy_opts})
  end

  ##
  # Callbacks

  @doc false
  def init(args) do
    port =
      case Keyword.get(args, :port, "") do
        "" -> @default_port
        p when is_binary(p) -> String.to_integer(p)
        p when is_integer(p) -> p
      end

    send(self(), {:listen, port})
    {:ok, %{listen_socket: nil}}
  end

  @doc false
  def handle_info({:listen, port}, state = %{listen_socket: nil}) do
    case :gen_tcp.listen(port, @upstream_tcp_opts) do
      {:ok, socket} ->
        Logger.debug("Listening on port: #{port}")
        {:noreply, %{listen_socket: socket}}

      {:error, reason} ->
        Logger.error("TCP Listen failed due to: #{inspect(reason)}")
        {:stop, :normal, state}
    end
  end

  def handle_info(msg, state) do
    Logger.warn("Unexpected message: #{inspect(msg)}}")
    {:noreply, state}
  end

  @doc false
  def handle_cast({:accept, proxy_opts}, state = %{listen_socket: socket}) do
    case :gen_tcp.accept(socket) do
      {:ok, upstream_socket} ->
        Logger.info("Connection accepted, spawning proxy server to manage connection")

        {:ok, proxy} =
          Chroxy.ProxyServer.start_link(
            upstream_socket: upstream_socket,
            proxy_opts: proxy_opts
          )

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
        Logger.error(
          "Upstream listen hit system limit all available ports in the Erlang emulator are in use"
        )

        {:stop, :normal, state}
    end
  end
end
