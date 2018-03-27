defmodule Chroxy.ChromeServer.Supervisor do
  @sup __MODULE__
  @worker Chroxy.ChromeServer

  def child_spec() do
    {DynamicSupervisor, name: @sup, strategy: :one_for_one}
  end

  def start_child(args) do
    DynamicSupervisor.start_child(@sup, @worker.child_spec(args))
  end

  def which_children() do
    DynamicSupervisor.which_children(@sup)
  end
end

defmodule Chroxy.ChromeServer do
  use GenServer
  require Logger

  alias ChromeRemoteInterface.Session

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

  def stop(server) do
    send(server, :stop)
  end

  def ready(server, opts \\ []) do
    retries = Keyword.get(opts, :retries, 5)
    wait_ms = Keyword.get(opts, :wait_ms, 1000)

    case GenServer.call(server, :ready, 30_000) do
      :not_ready ->
        if retries > 0 do
          Process.sleep(wait_ms)
          ready(server, retries: retries - 1, wait_ms: wait_ms)
        else
          :timeout
        end

      res ->
        res
    end
  end

  def list_pages(server) do
    GenServer.call(server, :list_pages)
  end

  def new_page(server) do
    GenServer.call(server, :new_page)
  end

  def close_page(server, page) do
    GenServer.call(server, {:close_page, page})
  end

  def close_all_pages(server) do
    GenServer.cast(server, :close_all_pages)
  end

  ##
  # GenServer callbacks

  def init(args) do
    config = Application.get_env(:chroxy, __MODULE__)
    page_wait_ms = Keyword.get(config, :page_wait_ms, 50)
    # TODO we will want to get the chrome browser options from config too
    opts = Keyword.merge(default_opts(), args)
    send(self(), :launch)
    {:ok, %{options: opts, session: nil, page_wait_ms: page_wait_ms}}
  end

  def handle_call(_, _from, state = %{session: nil}) do
    {:reply, :not_ready, state}
  end

  def handle_call(:ready, _from, state = %{session: _session}) do
    {:reply, :ready, state}
  end

  def handle_call(:list_pages, _from, state = %{session: session}) do
    {:ok, pages} = Session.list_pages(session)
    {:reply, pages, state}
  end

  def handle_call(:new_page, _from, state = %{session: session, page_wait_ms: page_wait_ms}) do
    {:ok, page} = Session.new_page(session)
    Process.sleep(page_wait_ms)
    {:reply, page, state}
  end

  def handle_call({:close_page, page}, _from, state = %{session: session}) do
    {:ok, _res} = Session.close_page(session, page["id"])
    {:reply, :ok, state}
  end

  def handle_cast(:close_all_pages, state = %{session: session}) do
    {:ok, pages} = Session.list_pages(session)

    Enum.each(pages, fn page ->
      Session.close_page(session, page["id"])
    end)

    {:noreply, state}
  end

  def handle_info(:stop, state) do
    {:stop, :normal, state}
  end

  def handle_info(:launch, state = %{options: opts}) do
    value_flags = ~w(
      --remote-debugging-port=#{opts[:chrome_port]}
      --crash-dumps-dir=/tmp
      --user-data-dir=/tmp
    )
    chrome_path = String.replace(opts[:chrome_path], " ", "\\ ")

    command =
      [chrome_path, opts[:chrome_flags], value_flags]
      |> List.flatten()
      |> Enum.join(" ")

    {:ok, pid, os_pid} = Exexec.run_link(command, exec_options())
    state = Map.merge(%{command: command, pid: pid, os_pid: os_pid}, state)
    {:noreply, state}
  end

  @log_head_size 19 * 8

  def handle_info({:stdout, pid, <<_::size(@log_head_size), ":WARNING:", msg::binary>>}, state) do
    msg = String.replace(msg, "\r\n", "")
    Logger.warn("[CHROME: #{inspect(pid)}] #{inspect(msg)}")
    {:noreply, state}
  end

  def handle_info(
        {:stdout, pid,
         <<_::size(@log_head_size),
           ":ERROR:socket_posix.cc(143)] bind() returned an error, errno=48: ", _msg::binary>>},
        state
      ) do
    Logger.error("[CHROME: #{inspect(pid)}] Address / Port already in use. terminating")
    # signal self termination as in bad state due to port conflict
    stop(self())
    {:noreply, state}
  end

  def handle_info({:stdout, pid, <<_::size(@log_head_size), ":ERROR:", msg::binary>>}, state) do
    msg = String.replace(msg, "\r\n", "")
    Logger.error("[CHROME: #{inspect(pid)}] #{inspect(msg)}")
    {:noreply, state}
  end

  def handle_info(
        {:stdout, pid, <<"\r\nDevTools listening on ", _rest::binary>> = msg},
        state = %{options: opts}
      ) do
    msg = String.replace(msg, "\r\n", "")
    Logger.info("[CHROME: #{inspect(pid)}] #{inspect(msg)}")
    chrome_port = Keyword.get(opts, :chrome_port)
    session = Session.new(port: chrome_port)
    {:noreply, %{state | session: session}}
  end

  def handle_info({:stdout, pid, msg}, state) do
    msg = String.replace(msg, "\r\n", "")
    Logger.info("[CHROME: #{inspect(pid)}] #{inspect(msg)}")
    {:noreply, state}
  end

  def handle_info({:stderr, pid, data}, state) do
    Logger.error("[CHROME: #{inspect(pid)}] #{inspect(data)}")
    {:noreply, state}
  end

  ##
  # Internal

  defp exec_options do
    %{pty: true, stdin: true, stdout: true, stderr: true}
  end

  defp default_opts do
    [
      chrome_port: 9222,
      chrome_path: chrome_path(),
      chrome_flags: ~w(
        --headless
        --disable-gpu
        --disable-translate
        --disable-extensions
        --disable-background-networking
        --safebrowsing-disable-auto-update
        --disable-sync
        --metrics-recording-only
        --disable-default-apps
        --mute-audio
        --no-first-run
      )
    ]
  end

  defp chrome_path do
    case :os.type() do
      {:unix, :darwin} ->
        "/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome"

      {:unix, _} ->
        "/usr/bin/google-chrome"
    end
  end
end
