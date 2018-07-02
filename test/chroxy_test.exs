defmodule ChroxyTest do
  use ExUnit.Case, async: true
  doctest Chroxy

  setup do
    page_url = Chroxy.connection()
    {:ok, page} = ChromeRemoteInterface.PageSession.start_link(page_url)
    [page: page]
  end

  test "connection should return ws:// endpoint" do
    endpoint = Chroxy.connection()
    ws_uri = URI.parse(endpoint)
    assert ws_uri.scheme == "ws"
  end

  test "can control page & register to events", context do
    page = context.page
    url = "https://github.com/holsee"
    ChromeRemoteInterface.RPC.Page.enable(page)
    ChromeRemoteInterface.PageSession.subscribe(page, "Page.loadEventFired", self())
    {:ok, _} = ChromeRemoteInterface.RPC.Page.navigate(page, %{url: url})
    assert_receive {:chrome_remote_interface, "Page.loadEventFired", _}, 5_000
  end

  test "out of order connections" do
    # Create 2 connections
    conn_0 = Chroxy.connection() |> IO.inspect()
    conn_1 = Chroxy.connection() |> IO.inspect()

    # Connect to 2nd connection first
    page_1 = ChromeRemoteInterface.PageSession.start_link(conn_1)
    page_0 = ChromeRemoteInterface.PageSession.start_link(conn_0)

    # Should not have crashed
    assert true
  end

end
