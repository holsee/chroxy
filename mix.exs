defmodule Chroxy.MixProject do
  use Mix.Project

  def project do
    [
      app: :chroxy,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Chroxy.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.5"},
      {:ranch, "~> 1.4"},
      {:cowboy, "~> 2.2"},
      {:jason, "~> 1.0"},
      {:erlexec, "~> 1.7"},
      {:exexec, "~> 0.1.0"}
    ]
  end
end
