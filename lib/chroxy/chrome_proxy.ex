defmodule Chroxy.ChromeProxy do
  @modueldoc """
  Reverse proxy that will manage connections to headless chrome instances
  """

  require Logger

  ##
  # API

  @doc """
  Initialise proxy server to route requests back for routing
  """
  def init() do
    proxy_port = 1337
    acceptor_pool = 100
    proxy_delegate = {__MODULE__, :proxy}

    {:ok, proxy_pid} =
      Chroxy.ProxyServer.serve(
        acceptor_pool,
        :ranch_tcp,
        [port: proxy_port],
        proxy: proxy_delegate
      )
  end

  ##
  # Callbacks

  @doc """
  Callback to establish connection
  """
  def proxy(data) do
    Logger.info("proxy delagate called with #{inspect(data)}")

    # ---------------------
    # TODO The following is the next focus, dynamic / remote spawning of chrome
    # servers which will be linked to incoming socket connections.
    # ---------------------
    host = {127, 0, 0, 1}
    port = 9223
    # _chrome_ws_endpoint = launch_chrome(chrome_port: port)
    # ---------------------

    Logger.info("Establishing proxy connection to: #{inspect(host)}:#{port}")
    [remote: {host, port}, data: data, reply: ""]
  end

  ##
  # Internal

  defp launch_chrome(args) do
    {:ok, pid} = Chroxy.ChromeServer.Supervisor.start_child(args)
    endpoint(pid)
  end

  defp endpoint(pid, retries \\ 5) do
    case Chroxy.ChromeServer.endpoint(pid) do
      :not_ready ->
        Process.sleep(1000)
        unless retries == 0, do: endpoint(pid, retries - 1)

      endpoint ->
        endpoint
    end
  end
end
