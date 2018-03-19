defmodule Chroxy do
  def launch(args) do
    {:ok, pid} = Chroxy.ChromeServer.start_link(args)
    endpoint(pid)
  end

  defp endpoint(pid) do
    case Chroxy.ChromeServer.endpoint(pid) do
      :not_ready ->
        Process.sleep(1000)
        endpoint(pid)

      endpoint ->
        endpoint
    end
  end
end
