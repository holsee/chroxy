defmodule Chroxy.MixProject do
  use Mix.Project

  def project do
    [
      app: :chroxy,
      version: "0.6.3",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: [main: "Chroxy", logo: "logo.png", extras: ["README.md"]]
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
      {:plug, "~> 1.8.0"},
      {:plug_cowboy, "~> 2.0.2"},
      {:cowboy, "~> 2.7.0"},
      {:jason, "~> 1.1"},
      {:erlexec, "~> 1.10.0"},
      {:exexec, "~> 0.2"},
      {:chrome_remote_interface, "~> 0.3.0"},
      {:ex_doc, "~> 0.20", only: :dev, runtime: false}
    ]
  end

  defp description() do
    "Chrome Proxy Service enabling scalable remote debug protocol connections to managed Headless Chrome instances."
  end

  defp package() do
    [
      name: "chroxy",
      files: ["config", "lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Steven Holdsworth (@holsee)"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/holsee/chroxy"}
    ]
  end
end
