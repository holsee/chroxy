defmodule Chroxy.ChromeServer do
  use GenServer
  require Logger

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def endpoint(server) do
    GenServer.call(server, :endpoint)
  end

  ##
  # GenServer callbacks

  def init(args)  do
    opts = Keyword.merge(default_opts(), args)
    send self(), :launch
    {:ok, %{options: opts}}
  end

  def handle_call(:endpoint, _from, state = %{options: options}) do
    {:reply, "ws://127.0.0.1:#{options[:chrome_port]}", state}
  end

  def handle_info(:launch, state = %{options: opts}) do
    value_flags = ~w(
      --remote-debugging-port=#{opts[:chrome_port]}
      --crash-dumps-dir=/tmp
      --user-data-dir=/tmp
    )
    chrome_path = String.replace(opts[:chrome_path], " ", "\\ ")
    command = [chrome_path, opts[:chrome_flags], value_flags]
              |> List.flatten
              |> Enum.join(" ")
    {:ok, pid, os_pid} = Exexec.run_link(command, exec_options())
    state = Map.merge(%{command: command, pid: pid, os_pid: os_pid}, state)
    {:noreply, state}
  end

  def handle_info({:stdout, pid, data}, state) do
    Logger.info("[#{pid}] #{inspect data}")
    {:noreply, state}
  end

  def handle_info({:stderr, pid, data}, state) do
    Logger.error("[#{pid}] #{inspect data}")
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
    case :os.type do
      {:unix, :darwin} ->
        "/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome"
      {:unix, _} ->
        "/usr/bin/google-chrome"
    end
  end

end

