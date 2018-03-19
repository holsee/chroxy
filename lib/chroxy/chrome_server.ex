defmodule ChromeLauncher do
  @moduledoc """
  Documentation for ChromeLauncher.
  """

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

  def start_link(opts \\ []), do: launch(opts)

  @doc """
  Launches an instance of Chrome.
  """
  @spec launch(list()) :: {:ok, pid()} | {:error, atom()}
  def launch(opts \\ []) do
    merged_opts = Keyword.merge(default_opts(), opts)

    case ChromeLauncher.Finder.find() do
      {:ok, path} ->
        cmd = [String.to_charlist(path) | formatted_flags(merged_opts)]
        parent = self()

        exec_opts = [
          stdout: fn(_, pid, data) ->
            Logger.info("[#{pid}] #{inspect(data)}")
          end,
          stderr: fn(_, pid, data) ->
            if !Process.get(:chrome_launched, false) && (:binary.match(data, "DevTools listening on ws://") != :nomatch) do
              send(parent, {:chrome_launched, pid})
              Process.put(:chrome_launched, true)
            end

            Logger.error("[#{pid}] #{inspect(data)}")
          end
        ]

        with \
          {:ok, pid, os_pid} <- :exec.run_link(cmd, exec_opts),
          {:ok, _os_pid} <- wait_for_chrome_to_launch(os_pid)
        do
          {:ok, pid}
        else
          error ->
            error
        end
      {:error, _} = error ->
        error
    end
  end

  def default_opts() do
    [
      remote_debugging_port: 9222,
      flags: [
        "--headless",
        "--disable-gpu",
        "--disable-translate",
        "--disable-extensions",
        "--disable-background-networking",
        "--safebrowsing-disable-auto-update",
        "--disable-sync",
        "--metrics-recording-only",
        "--disable-default-apps",
        "--mute-audio",
        "--no-first-run"
      ]
    ]
  end

  defp wait_for_chrome_to_launch(os_pid) do
    receive do
      {:chrome_launched, ^os_pid} ->
        {:ok, os_pid}
    after
      10_000 ->
        :exec.kill(os_pid, 15)
        {:error, :process_did_not_launch}
    end
  end

  defp formatted_flags(opts) do
    tmp_dir = System.tmp_dir()
    user_data_dir = System.tmp_dir()

    internal_flags = [
      "--remote-debugging-port=#{opts[:remote_debugging_port]}",
      "--crash-dumps-dir=#{tmp_dir}",
      "--user-data-dir=#{user_data_dir}"
    ]

    (internal_flags ++ List.wrap(opts[:flags]))
    |> Enum.map(&String.to_charlist/1)
  end
end
