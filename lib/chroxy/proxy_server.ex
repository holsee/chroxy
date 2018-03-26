defmodule Chroxy.ProxyServer do
  use GenServer

  require Logger

  defmodule Hook do
    @callback up(identifier(), Keyword.t) :: [
                downstream_host: charlist(),
                downstream_port: non_neg_integer()
              ]
    @callback down(identifier(), Map.t()) :: :ok
    @optional_callbacks up: 2, down: 2
  end

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
    # Proxy can be configured to callback to another module
    # which will optionally implement hook functions
    proxy_opts = Keyword.get(args, :proxy_opts)
    hook = Keyword.get(proxy_opts, :hook)
    hook_opts =
      if hook && function_exported?(hook.mod, :up, 2) do
        apply(hook.mod, :up, [hook.ref, args])
      end
    opts = Keyword.merge(proxy_opts, hook_opts || [])
    downstream_host = Keyword.get(opts, :downstream_host)
    downstream_port = Keyword.get(opts, :downstream_port)
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
       },
       hook: hook
     }}
  end

  def handle_info(:init_downstream, state = %{downstream: downstream}) do
    {:ok, down_socket} = :gen_tcp.connect(downstream.host, downstream.port, downstream.tcp_opts)
    Logger.debug("Downstream connection established")

    {:noreply,
     %{
       state
       | downstream: %{
           downstream
           | socket: down_socket
         }
     }}
  end

  def handle_info(
        {:tcp, downstream_socket, data},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket}}
      ) do
    Logger.debug("Up <- Down: #{inspect(data)}")
    :gen_tcp.send(upstream_socket, data)
    {:noreply, state}
  end

  def handle_info(
        {:tcp, upstream_socket, data},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket}}
      ) do
    Logger.debug("Up -> Down: #{inspect(data)}")
    :gen_tcp.send(downstream_socket, data)
    {:noreply, state}
  end

  def handle_info(
        {:tcp_closed, upstream_socket},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket}}
      ) do
    Logger.debug("Upstream socket closed, terminating proxy")

    hook = Map.get(state, :hook)
    if hook && function_exported?(hook.mod, :down, 2) do
      apply(hook.mod, :down, [hook.ref, state])
    end

    :gen_tcp.close(downstream_socket)
    :gen_tcp.close(upstream_socket)
    {:stop, :normal, state}
  end

  def handle_info(
        {:tcp_closed, downstream_socket},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket}}
      ) do
    Logger.warn("Downstream socket closed, terminating proxy")

    hook = Map.get(state, :hook)
    if hook && function_exported?(hook.mod, :down, 2) do
      apply(hook.mod, :down, [hook.ref, state])
    end

    :gen_tcp.close(downstream_socket)
    :gen_tcp.close(upstream_socket)
    {:stop, :normal, state}
  end

end
