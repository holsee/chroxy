defmodule Chroxy do
  @doc """
  Initialise proxy to instance of Chrome
  """
  def new do
    {:ok, pid} = Chroxy.ChromeServer.start_link([])
    Chroxy.ChromeServer.endpoint(pid)
  end
end
