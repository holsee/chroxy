defmodule Chroxy.Endpoint do
  use Plug.Router

  plug(Plug.Logger)
  plug(Plug.RequestId)
  plug(:match)
  plug(:dispatch)

  get "/api/v1/connection" do
    endpoint = Chroxy.new()
    send_resp(conn, 200, endpoint)
  end

  match _ do
    send_resp(conn, 404, "oops")
  end
end
