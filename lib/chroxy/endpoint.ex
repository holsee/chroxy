defmodule Chroxy.Endpoint do
  use Plug.Router

  plug(Plug.Logger)
  plug(Plug.RequestId)
  plug(:match)
  plug(:dispatch)

  get "/api/v1/connection" do
    # spawn proxy, link to chrome
    # return websocket path routing via proxy
    send_resp(conn, 200, "not_implemented")
  end

  match _ do
    send_resp(conn, 404, "oops")
  end
end
