defmodule Chroxy.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  def start(_type, _args) do
    chroxy_opts = Application.get_all_env(:chroxy)
    children = [
      Chroxy.ChromeServer.Supervisor.child_spec(),
      Chroxy.child_spec(chroxy_opts),
      Chroxy.Endpoint.child_spec()
    ]

    Logger.info("Started application")

    opts = [strategy: :one_for_one, name: Chroxy.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
