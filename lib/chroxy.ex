defmodule Chroxy.Endpoint do
  use Plug.Router
  require Logger

  plug(Plug.Logger)
  plug(Plug.RequestId)
  plug BasicAuth, use_config: {:chroxy, :your_config}
  plug(:match)matcho
  plug(:dispatch)


  plug(
    Plug.Parsers,
    parsers: [:json],
    pass: ["text/*"],
    json_decoder: Jason
  )

  get "/api/v1/connection" do
    :ok = ChromeServer.start(remote_debugging_port: chrome_port)
    :ok = Chroxy.new(target: chrome_port)
    send_resp(conn, 200, "ws://lol")
  end

  match _ do
    send_resp(conn, 404, "oops")
  end
end
