defmodule Chroxy.ProxyServer do
  @moduledoc """
  Transparent Proxy Server manages the relay of communications between and
  upstream and downstream tcp connections. Support customer extensions through
  callbacks of Hook modules which implement the `Chroxy.ProxyServer.Hook` behaviour.
  """
  use GenServer

  require Logger

  defmodule Hook do
    @moduledoc """
    Behaviour for Proxy Server Hooks.
    Example: `Chroxy.ChromeProxy`
    """

    @doc """
    Optional callback invoked when `Chroxy.ProxyServer` is initialised
    which allows for inteception and addition to the `proxy_opts`
    used by the proxy server.  Useful for initialising downstream
    resources, and passing `:downstream_host` & `:downstream_port`
    for use by `Chroxy.ProxyServer`.
    """
    @callback up(identifier(), Keyword.t()) :: [
                downstream_host: charlist(),
                downstream_port: non_neg_integer()
              ]

    @doc """
    Optional callback which is invoked when either the upstream
    or downstream connections are closed.  Useful for cleaning up resources
    which may have been linked to the lifetime of the proxy connection.
    """
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

  @doc """
  Spawns a process to manage connections between upstream and downstream
  connections.

  Keyword `args`:
  * `:upstream_socket` - `:gen_tcp` connection delegated from the `Chroxy.ProxyListener`
  * `:proxy_opts`:
    * `:downstream_host` - host for downstream connection
    * `:downstream_port` - port for downstream conenction
    * `:hook` - name of a module which implements `Chroxy.ProxyServer.Hook`
  """
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @doc false
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

    # check args for packet_trace, otherwise check config
    packet_trace =
      Keyword.get(opts, :packet_trace, false) ||
        Application.get_env(:chroxy, Chroxy.ProxyServer, [])
        |> Keyword.get(:packet_trace, false)

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
       hook: hook,
       packet_trace: packet_trace
     }}
  end

  @doc false
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
    if state.packet_trace do
      Logger.debug("Up <- Down: #{inspect(data)}")
    end

    :gen_tcp.send(upstream_socket, data)
    {:noreply, state}
  end

  def handle_info(
        {:tcp, upstream_socket, data},
        state = %{upstream: %{socket: upstream_socket}, downstream: %{socket: downstream_socket}}
      ) do
    if state.packet_trace do
      Logger.debug("Up -> Down: #{inspect(data)}")
    end

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
