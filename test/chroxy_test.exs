defmodule ChroxyTest do
  use ExUnit.Case
  doctest Chroxy

  test "connection should return ws:// endpoint" do
    endpoint = Chroxy.connection()
    ws_uri = URI.parse(endpoint)
    assert ws_uri.scheme == "ws"
  end
end
