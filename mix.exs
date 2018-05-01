defmodule Chroxy.MixProject do
  use Mix.Project

  def project do
    [
      app: :chroxy,
      version: "0.2.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :erlexec, :exexec],
      mod: {Chroxy.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.5"},
      {:cowboy, "~> 1.1"},
      {:jason, "~> 1.0"},
      {:erlexec, "~> 1.1.3"},
      {:exexec, "~> 0.0.1"},
      {:chrome_remote_interface, "~> 0.1.0"}
    ]
  end
end
