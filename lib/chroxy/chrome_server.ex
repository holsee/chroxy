defmodule Chroxy.ChromeServer.Supervisor do
  @moduledoc """
  `DynamicSupervisor` for `Chroxy.ChromeServer`
  """

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
  @moduledoc """
  `GenServer` process which manages a port connection to a Chrome
  browser OS Process as well as a `ChromeRemoteInterface.Session` to
  the browser instance providing command and control over the instance.

  The `stdout` and `stderr` messages from the os process are captured
  and are used to determine state transitions, namely when the browser
  is ready to start accepting connections, and when the browser enters
  a critical error state and must be terminated.
  """

  use GenServer
  require Logger

  alias ChromeRemoteInterface.Session

  @ready_check_ms 30_000

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  @doc """
  Spanws a `Chroxy.ChromeServer` process which in turn starts an underlying
  chrome browser os process, which is managed by a shared lifetime allowing
  for managing Chrome Browser within an OTP Supervision model.
  """
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @doc """
  Blocks and performs a poll of the underlying `Chroxy.ChromeServer` to determine when
  the chrome browser instance is ready for interaction.

  Keyword `opts`:
  * `:retries` - number to times to poll for _ready_ state.
  * `:wait_ms` - how long to _sleep_ between polling calls.
  * `:crash_dumps_dir` - where chrome should write crash dumps.
  """
  def ready(server, opts \\ []) do
    retries = Keyword.get(opts, :retries, 5)
    wait_ms = Keyword.get(opts, :wait_ms, 1000)

    try do
      case GenServer.call(server, :ready, 30_000) do
        :not_ready ->
          if retries > 0 do
            Process.sleep(wait_ms)
            ready(server, retries: retries - 1, wait_ms: wait_ms)
          else
            :timeout
          end

        :ready ->
          :ready
      end
    catch
      :exit, _ ->
        Logger.error("ChromeServer #{inspect(server)} did not reply to ready request")
        :timeout
    end
  end

  @doc """
  Lists page sessions currently open to the chrome instance.
  """
  def list_pages(server) do
    GenServer.call(server, :list_pages)
  end

  @doc """
  Creates a new chrome page (tab) within the chrome instance.
  """
  def new_page(server) do
    GenServer.call(server, :new_page)
  end

  @doc """
  Closes the page in the chrome instance.
  """
  def close_page(server, page) do
    GenServer.cast(server, {:close_page, page})
  end

  @doc """
  Closes all open pages in the chrome instance.
  """
  def close_all_pages(server) do
    GenServer.cast(server, :close_all_pages)
  end

  ##
  # GenServer callbacks

  @doc false
  def terminate(reason, state) do
    Logger.warn("ChromeServer terminating - #{inspect(state)} - reason: #{reason}")
    :ok
  end

  @doc false
  def init(args) do
    config = Application.get_env(:chroxy, __MODULE__)

    opts =
      default_opts()
      |> Keyword.merge(config)
      |> Keyword.merge(args)

    page_wait_ms = Keyword.get(config, :page_wait_ms) |> String.to_integer()
    send(self(), :launch)
    Process.send_after(self(), :stop_if_not_ready, @ready_check_ms)
    {:ok, %{options: opts, session: nil, page_wait_ms: page_wait_ms}}
  end

  @doc false
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

  @doc false
  def handle_cast({:close_page, page}, state = %{session: session}) do
    Session.close_page(session, page["id"])
    {:noreply, state}
  end

  def handle_cast(:close_all_pages, state = %{session: session}) do
    {:ok, pages} = Session.list_pages(session)

    Enum.each(pages, fn page ->
      Session.close_page(session, page["id"])
    end)

    {:noreply, state}
  end

  @doc false
  def handle_info(:launch, state = %{options: opts}) do
    value_flags = ~w(
        --remote-debugging-port=#{opts[:chrome_port]}
        --crash-dumps-dir=#{opts[:crash_dumps_dir]}
        --v=#{opts[:verbose_logging]}
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

  def handle_info(:stop_if_not_ready, state = %{session: nil, os_pid: os_pid}) do
    Logger.warn("Chrome failed to start within #{@ready_check_ms} ms, self terminating.")
    Exexec.stop_and_wait(os_pid)
    {:stop, :normal, state}
  end

  def handle_info(:stop_if_not_ready, state) do
    {:noreply, state}
  end

  @log_head_size 19 * 8

  def handle_info({:stdout, pid, <<_::size(@log_head_size), ":WARNING:", msg::binary>>}, state) do
    msg = String.replace(msg, "\r\n", "")
    Logger.warn("[CHROME: #{inspect(pid)}] #{inspect(msg)}")
    {:noreply, state}
  end

  def handle_info(
        {source, pid,
         <<_::size(@log_head_size), ":ERROR:socket_posix.cc(143)] bind()", _msg::binary>>},
        state
      )
      when source == :stdout or source == :stderr do
    Logger.error("[CHROME: #{inspect(pid)}] Address / Port already in use. terminating")
    Exexec.stop_and_wait(pid)
    {:stop, :normal, state}
  end

  def handle_info(
        {:stdout, pid,
         <<_::size(@log_head_size), ":ERROR:crash_handler_host_linux.cc", _rest::binary>> = msg},
        state
      ) do
    Logger.error("[CHROME: #{inspect(pid)}] #{msg}")
    Logger.error("[CHROME: #{inspect(pid)}] Critical State - Terminating.")
    Exexec.stop_and_wait(pid)
    {:stop, :normal, state}
  end

  def handle_info({:stdout, pid, <<_::size(@log_head_size), ":ERROR:", msg::binary>>}, state) do
    msg = String.replace(msg, "\r\n", "")
    Logger.error("[CHROME: #{inspect(pid)}] #{inspect(msg)}")
    {:noreply, state}
  end

  def handle_info({device, pid, <<_::size(@log_head_size), ":VERBOSE1:", msg::binary>>}, state)
    when device == :stdout or device == :stderr do
    msg = String.replace(msg, "\r\n", "")
    Logger.debug("[CHROME: #{inspect(pid)}] #{inspect(msg)}")
    {:noreply, state}
  end

  # TODO refactor messages from logs to remove "\r\n" once / create module to
  # handle log parsing
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

  def handle_info(
        {:stdout, pid, <<"DevTools listening on ", _rest::binary>> = msg},
        state = %{options: opts}
      ) do
    msg = String.replace(msg, "\r\n", "")
    Logger.info("[CHROME: #{inspect(pid)}] #{inspect(msg)}")
    chrome_port = Keyword.get(opts, :chrome_port)
    session = Session.new(port: chrome_port)
    {:noreply, %{state | session: session}}
  end

  def handle_info({:stderr, pid, <<"crash_handler_host_linux.cc", _rest::binary>> = msg}, state) do
    Logger.error("[CHROME: #{inspect(pid)}] #{msg}")
    Logger.error("[CHROME: #{inspect(pid)}] Critical State - Terminating.")
    Exexec.stop_and_wait(pid)
    {:stop, :normal, state}
  end

  def handle_info({:stdout, pid, <<"Failed to generate minidump.", _rest::binary>> = msg}, state) do
    Logger.error("[CHROME: #{inspect(pid)}] #{msg}")
    Logger.error("[CHROME: #{inspect(pid)}] Critical State - Terminating.")
    Exexec.stop_and_wait(pid)
    {:stop, :normal, state}
  end

  ##
  # Catch all

  def handle_info({:stdout, pid, msg}, state) do
    msg = String.replace(msg, "\r\n", "")

    unless msg == "" do
      Logger.info("[CHROME: #{inspect(pid)}] stdout: #{inspect(msg)}")
    end

    {:noreply, state}
  end

  def handle_info({:stderr, pid, msg}, state) do
    msg = String.replace(msg, "\r\n", "")

    unless msg == "" do
      Logger.error("[CHROME: #{inspect(pid)}] stderr: #{inspect(msg)}")
    end

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
        --enable-logging
        --disable-sync
        --metrics-recording-only
        --disable-default-apps
        --mute-audio
        --no-first-run
        --no-sandbox
        --incognito
      ),
      verbose_logging: 0,
      crash_dumps_dir: "/tmp"
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
