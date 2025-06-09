defmodule ExMachine.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_machine,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      source_url: "https://github.com/USER/PROJECT",
      homepage_url: "http://YOUR_PROJECT_HOMEPAGE",
      docs: [
        main: "readme",
        extras: ["README.md"],
        #logo: "path/to/logo.png"
      ],
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
end
