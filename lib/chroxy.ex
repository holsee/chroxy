defmodule Chroxy do
  @moduledoc """
  Provides Chrome Remote Debug Protocol connections.
  """

  @type url :: String.t()

  @doc """
  Provides a web socket address for a remote debug session.
  Once a connection is established the chrome page will be initialised
  and once the connection is closed, the chrome page will be closed.
  """
  @spec connection() :: url()
  def connection do
    Chroxy.BrowserPool.connection(:chrome)
  end
end
