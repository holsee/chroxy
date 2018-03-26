defmodule Chroxy.ChromeProxy do

  @behaviour Chroxy.ProxyServer.Hook

  require Logger

  @doc """
  Called when Proxy is initialising.
  """
  def up(_args) do
    Logger.info("UP CALLED")
    []
  end

  @doc """
  Called when upstream or downstream connections are closed
  """
  def down(_state) do
    Logger.info("DOWN CALLED")
    :ok
  end

end
