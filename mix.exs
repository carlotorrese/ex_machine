defmodule ExMachine.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_machine,
      version: "0.1.1",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      description: description(),
      package: package(),
      source_url: "https://github.com/carlotorrese/ex_machine",
      homepage_url: "https://github.com/carlotorrese/ex_machine",
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end

  defp elixirc_paths(:dev), do: ["lib", "samples"]
  defp elixirc_paths(:test), do: ["lib", "samples"]
  defp elixirc_paths(_), do: ["lib"]

  defp description() do
    "An Elixir functional implementation of a finite state machine, based on Statechart formalism. [ALPHA - API may change]"
  end

  defp package() do
    [
      name: "ex_machine",
      files: ~w(lib mix.exs README* LICENSE* CHANGELOG*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/carlotorrese/ex_machine",
        "Changelog" => "https://github.com/carlotorrese/ex_machine/blob/main/CHANGELOG.md"
      },
      maintainers: ["Carlo Torrese"]
    ]
  end

  defp docs() do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      source_ref: "v#{version()}",
      source_url: "https://github.com/carlotorrese/ex_machine"
    ]
  end

  defp version(), do: "0.1.1"
end
