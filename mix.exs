defmodule ExMachine.MixProject do
  use Mix.Project

  @version "0.2.0-alpha.1"
  @source_url "https://github.com/carlotorrese/ex_machine"

  def project do
    [
      app: :ex_machine,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() != :test,
      description: description(),
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ExMachine.Application, []}
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 1.2"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "Functional hierarchical state machine for Elixir, based on the Statechart formalism (Harel/SCXML). Supports hierarchical states, parallel regions, history, choice pseudostates, guards and actions, with optional GenServer-mode for delayed events and invoked services."
  end

  defp package do
    [
      name: "ex_machine",
      files: ~w(lib mix.exs README* CHANGELOG* LICENSE* guides),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["Carlo Torrese"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras:
        [
          "README.md",
          "CHANGELOG.md",
          "LICENSE"
        ] ++ Path.wildcard("guides/*.md"),
      groups_for_extras: [Guides: ~r"^guides/"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
