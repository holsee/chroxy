defmodule Chroxy.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  def start(_type, _args) do
    endpoint_opts = Application.get_env(:chroxy, Chroxy.Endpoint)
    endpoint_port = endpoint_opts[:port]
    endpoint_scheme = endpoint_opts[:scheme]
    endpoint_spec = {Plug.Adapters.Cowboy2,
      scheme: endpoint_scheme, plug: Chroxy.Endpoint, options: [port: endpoint_port]}
    children = [
      endpoint_spec
    ]

    Logger.info("Started application")

    opts = [strategy: :one_for_one, name: Chroxy.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
