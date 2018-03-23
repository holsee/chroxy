defmodule Chroxy.ProxyServer do
  @behaviour :ranch_protocol

  require Logger

  @default_socket_opts [packet: 0, active: :once]
  @default_timeout 1000 * 60

  defmodule State do
    defstruct socket: nil,
              socket_opts: nil,
              transport: nil,
              proxy: nil,
              buffer: <<>>,
              remote_endpoint: nil,
              remote_socket: nil,
              remote_transport: nil,
              remote_socket_opts: nil,
              remote_connect_fun: nil,
              timeout: nil

    @type t(
            socket,
            socket_opts,
            transport,
            proxy,
            buffer,
            remote_endpoint,
            remote_socket,
            remote_transport,
            remote_socket_opts,
            remote_connect_fun,
            timeout
          ) :: %State{
            socket: socket,
            socket_opts: socket_opts,
            transport: transport,
            proxy: proxy,
            buffer: buffer,
            remote_endpoint: remote_endpoint,
            remote_socket: remote_socket,
            remote_transport: remote_transport,
            remote_socket_opts: remote_socket_opts,
            remote_connect_fun: remote_connect_fun,
            timeout: timeout
          }

    @type t :: %State{
            socket: :inet.socket(),
            socket_opts: [:gen_tcp.option()],
            transport: module(),
            proxy: {module(), atom()} | fun(),
            buffer: binary(),
            remote_endpoint: any(),
            remote_socket: :inet.socket(),
            remote_transport: module(),
            remote_socket_opts: module(),
            remote_connect_fun: function(),
            timeout: non_neg_integer()
          }
  end

  ##
  # API

  def serve(listeners, protocol, protocol_opts, proxy_opts) do
    {:ok, _} =
      :ranch.start_listener(
        __MODULE__,
        listeners,
        protocol,
        protocol_opts,
        __MODULE__,
        proxy_opts
      )
  end

  ##
  # Callbacks

  def start_link(listener_pid, socket, transport, opts) do
    pid = spawn_link(__MODULE__, :init, [listener_pid, socket, transport, opts])
    {:ok, pid}
  end

  def init(listener_pid, socket, transport, opts) do
    :ok = :ranch.accept_ack(listener_pid)

    loop(%State{
      socket: socket,
      transport: transport,
      proxy: Keyword.get(opts, :proxy),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      socket_opts: Keyword.get(opts, :source_opts, @default_socket_opts),
      remote_socket_opts: Keyword.get(opts, :remote_opts, @default_socket_opts),
      remote_connect_fun: Keyword.get(opts, :remote_connect, &remote_connect/1)
    })
  end

  ##
  # Internal

  defp loop(
         state = %State{
           socket: socket,
           transport: transport,
           proxy: proxy,
           timeout: timeout
         }
       ) do
    case apply(transport, :recv, [socket, 0, timeout]) do
      {:ok, data} ->
        buffer = <<state.buffer::binary(), data::binary()>>

        case run_proxy(proxy, buffer) do
          :stop ->
            terminate(state)

          :ignore ->
            loop(state)

          buffer: new_data ->
            loop(%State{state | buffer: new_data})

          remote: remote ->
            start_proxy_loop(%State{state | buffer: buffer, remote_endpoint: remote})

          [remote: remote, data: new_data, reply: reply] ->
            apply(transport, :send, [socket, reply])
            start_proxy_loop(%State{state | buffer: new_data, remote_endpoint: remote})

          _ ->
            loop(%State{state | buffer: buffer})
        end

      _ ->
        terminate(state)
    end
  end

  defp start_proxy_loop(state = %State{remote_endpoint: remote, buffer: buffer}) do
    case remote_connect(remote) do
      {transport, {:ok, socket}} ->
        apply(transport, :send, [socket, buffer])

        proxy_loop(%State{
          state
          | remote_socket: socket,
            remote_transport: transport,
            buffer: <<>>
        })

      {_, {:error, _error}} ->
        terminate(state)
    end
  end

  defp proxy_loop(
         state = %State{
           socket: socket,
           transport: transport,
           remote_socket: remote_socket,
           remote_transport: remote_transport,
           socket_opts: socket_opts,
           remote_socket_opts: remote_socket_opts
         }
       ) do
    apply(transport, :setopts, [socket, socket_opts])
    apply(remote_transport, :setopts, [remote_socket, remote_socket_opts])

    receive do
      {_, ^socket, data} ->
        Logger.info("Up => Proxy => Remote : #{inspect(data)}")
        apply(remote_transport, :send, [remote_socket, data])
        proxy_loop(state)

      {_, ^remote_socket, data} ->
        Logger.info("Up <= Proxy <= Remote : #{inspect(data)}")
        apply(transport, :send, [socket, data])
        proxy_loop(state)

      {:tcp_closed, ^remote_socket} ->
        Logger.info("Remote Socket closed.")
        terminate(state)

      {:tcp_closed, ^socket} ->
        Logger.info("Upstream Socket closed.")
        terminate_remote(state)

      msg ->
        Logger.warn("Closing connections, unexpected message: #{msg}")
        terminate_all(state)
    end
  end

  defp remote_connect({ip, port}) do
    {:ranch_tcp, :gen_tcp.connect(ip, port, [:binary, packet: 0, delay_send: true])}
  end

  defp run_proxy({mod, fun}, data) do
    apply(mod, fun, [data])
  end
  defp run_proxy(fun, data) when is_function(fun) do
    fun.(data)
  end

  defp terminate(%State{socket: socket, transport: transport}) do
    apply(transport, :close, [socket])
  end

  defp terminate_remote(%State{remote_socket: socket, remote_transport: transport}) do
    apply(transport, :close, [socket])
  end

  defp terminate_all(state) do
    terminate_remote(state)
    terminate(state)
  end
end
