defmodule Chroxy.Proxy do
  use GenServer
  require Logger


  def child_spec() do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    opts = [
      proxy:  Keyword.merge(default_opts(:proxy), opts[:proxy],
      target: Keyword.merge(default_opts(:target), opts[:target]
    ]
    {:ok, opts}
  end

  def default_opts(:proxy) do
    [
      port: 0, #  delagate to OS for port
      backlog: 10_000
    ]
  end

  def default_opts(:target) do
    [
      port: 9222, # default chrome debug protocol port
      host: {127,0,0,1}
    ]
  end

  def run(proxy: proxy_opts) do
    proxy_port = proxy_opts[:port]
    {:ok, socket} = :gen_tcp.listen(proxy_port, opts)
    Logger.info("Listening for connections on port #{proxy_port}")
    accept(socket)
  end

  defp accept(socket) do
    {:ok, client_socket} = :gen_tcp.accept(socket)

    handler =
      spawn(fn ->
        receive do
          :go -> :go
        end

        opts = [
          :binary,
          nodelay: true,
          packet: 0,
          active: true
        ]

        {:ok, target_socket} = :gen_tcp.connect(@localhost, @port_to, opts)
        loop(target_socket, client_socket)
      end)

    :gen_tcp.controlling_process(client_socket, handler)
    send(handler, :go)
    accept(socket)
  end

  defp loop(target_socket, client_socket) do
    continue? =
      receive do
        {:tcp, ^target_socket, data} ->
          Logger.info("Target => Server : #{inspect(data)}")
          :ok == :gen_tcp.send(client_socket, data)

        {:tcp, ^client_socket, data} ->
          Logger.info("Target <= Server : #{inspect(data)}")
          :ok == :gen_tcp.send(target_socket, data)

        {:tcp_closed, ^client_socket} ->
          Logger.info("Server connection closed, closing client connection.")
          :gen_tcp.close(target_socket)
          :gen_tcp.close(client_socket)
          false

        {:tcp_closed, ^target_socket} ->
          Logger.info("Client connection closed, closing server connection.")
          :gen_tcp.close(target_socket)
          :gen_tcp.close(client_socket)
          false
      end

    if continue? do
      loop(target_socket, client_socket)
    else
      :ok
    end
  end
end
