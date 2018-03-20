defmodule Chroxy do
  def launch(args) do
    {:ok, pid} = Chroxy.ChromeServer.start_link(args)
    endpoint(pid)
  end

  defp endpoint(pid, retries \\ 5) do
    case Chroxy.ChromeServer.endpoint(pid) do
      :not_ready ->
        Process.sleep(1000)
        unless retries == 0, do: endpoint(pid, retries-1)
      endpoint ->
        endpoint
    end
  end
end
