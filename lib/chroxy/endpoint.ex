defmodule Chroxy.Endpoint do
  use Plug.Router

  plug(Plug.Logger)
  plug(Plug.RequestId)
  plug(:match)
  plug(:dispatch)

  def child_spec() do
    endpoint_opts = Application.get_env(:chroxy, Chroxy.Endpoint)
    endpoint_port = endpoint_opts[:port] |> String.to_integer()
    endpoint_scheme = endpoint_opts[:scheme]

    {Plug.Adapters.Cowboy,
     scheme: endpoint_scheme, plug: Chroxy.Endpoint, options: [port: endpoint_port]}
  end

  get "/api/v1/connection" do
    endpoint = Chroxy.connection()
    send_resp(conn, 200, endpoint)
  end

  match _ do
    send_resp(conn, 404, "oops")
  end
end
