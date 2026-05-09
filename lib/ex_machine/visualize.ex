defmodule ExMachine.Visualize do
  @moduledoc """
  Render an `ExMachine.Definition` (or a statechart module) to formats
  that external tools can display.

  Two backends ship in v0.2:

    * `to_mermaid/2` — Mermaid `stateDiagram-v2` string. Paste into
      [mermaid.live](https://mermaid.live) or any Markdown renderer
      that supports Mermaid.
    * `to_scxml/2` — W3C SCXML XML string. Feed to tools like
      [statechart.io](https://statechart.io/) or W3C's reference
      implementations.

  Both renderers read the `ExMachine.Definition` only — they never
  start a machine, never call into `Engine` / `Server`, and have no
  side effects. They are safe to call at compile time.

  ## Examples

      iex> defmodule TL do
      ...>   use ExMachine.Statechart
      ...>   initial :red
      ...>   state :red,    do: on(:timer, target: :green)
      ...>   state :green,  do: on(:timer, target: :yellow)
      ...>   state :yellow, do: on(:timer, target: :red)
      ...> end
      iex> ExMachine.Visualize.to_mermaid(TL) |> String.split("\\n") |> hd()
      "stateDiagram-v2"
  """

  alias ExMachine.Definition
  alias ExMachine.Visualize.{Mermaid, Scxml}

  @type source :: module() | Definition.t()

  @doc "Render to Mermaid `stateDiagram-v2` source."
  @spec to_mermaid(source(), keyword()) :: String.t()
  def to_mermaid(source, opts \\ [])
  def to_mermaid(mod, opts) when is_atom(mod), do: to_mermaid(mod.__statechart__(), opts)
  def to_mermaid(%Definition{} = def_, opts), do: Mermaid.render(def_, opts)

  @doc "Render to W3C SCXML XML source."
  @spec to_scxml(source(), keyword()) :: String.t()
  def to_scxml(source, opts \\ [])
  def to_scxml(mod, opts) when is_atom(mod), do: to_scxml(mod.__statechart__(), opts)
  def to_scxml(%Definition{} = def_, opts), do: Scxml.render(def_, opts)
end
