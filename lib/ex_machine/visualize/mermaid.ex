defmodule ExMachine.Visualize.Mermaid do
  @moduledoc """
  Render an `ExMachine.Definition` to Mermaid `stateDiagram-v2`.

  ## Mapping

    * **atomic** — implicit; appears only as the endpoint of arrows.
    * **compound** — `state Name { ... }` block. Its `:initial` becomes
      `[*] --> initial` inside the block.
    * **parallel** — `state Name { ... }` containing each region's
      block separated by `--`.
    * **region** — nested `state Name { ... }` with its own initial
      arrow.
    * **final** — arrows targeting it become `Source --> [*]`. The node
      itself is not declared.
    * **history** — `state H <<history>>`. Mermaid stateDiagram-v2 has
      no separate marker for deep history; both shallow and deep map
      to `<<history>>`.
    * **choice** — `state C <<choice>>`.

  Transitions render as `Source --> Target: event`, or just
  `Source --> Target` for an eventless transition. Guards and actions
  are not surfaced — Mermaid is a structural view; consult the source
  for behavioural detail.
  """

  alias ExMachine.{Definition, StateNode}

  @indent_unit "  "

  @doc "Render `definition` to Mermaid source."
  @spec render(Definition.t(), keyword()) :: String.t()
  def render(%Definition{} = def_, _opts \\ []) do
    root = Definition.fetch!(def_, def_.root)
    body = render_root(root, def_)
    Enum.join(["stateDiagram-v2" | body], "\n")
  end

  # ── Root ─────────────────────────────────────────────────────────────────

  defp render_root(%StateNode{kind: :compound} = root, def_) do
    render_compound_body(root, def_, 1) ++ render_transitions(root, def_, 1)
  end

  defp render_root(%StateNode{kind: :parallel} = root, def_) do
    render_parallel_body(root, def_, 1) ++ render_transitions(root, def_, 1)
  end

  # ── Bodies (the contents of a `state X { ... }` block) ───────────────────

  defp render_compound_body(%StateNode{} = node, def_, level) do
    initial_arrow(node, level) ++ child_lines(node, def_, level)
  end

  defp render_parallel_body(%StateNode{} = parallel, def_, level) do
    parallel.substates
    |> Enum.map(fn region_id ->
      region = Definition.fetch!(def_, region_id)
      child_section(region, def_, level)
    end)
    |> Enum.intersperse([indent(level, "--")])
    |> List.flatten()
  end

  # The lines emitted INSIDE a parent block for one of its children: the
  # child's own declaration (block / pseudostate marker / nothing) followed
  # by the child's outgoing transitions at this same level.
  defp child_lines(%StateNode{} = node, def_, level) do
    Enum.flat_map(node.substates, fn child_id ->
      child = Definition.fetch!(def_, child_id)
      child_section(child, def_, level)
    end)
  end

  defp child_section(%StateNode{} = child, def_, level) do
    declaration(child, def_, level) ++ render_transitions(child, def_, level)
  end

  # ── Declarations ─────────────────────────────────────────────────────────

  defp declaration(%StateNode{kind: :atomic}, _def_, _level), do: []
  defp declaration(%StateNode{kind: :final}, _def_, _level), do: []

  defp declaration(%StateNode{kind: :history, id: id}, _def_, level) do
    [indent(level, "state #{name(id)} <<history>>")]
  end

  defp declaration(%StateNode{kind: :choice, id: id}, _def_, level) do
    [indent(level, "state #{name(id)} <<choice>>")]
  end

  defp declaration(%StateNode{kind: :compound} = node, def_, level) do
    block(node, render_compound_body(node, def_, level + 1), level)
  end

  defp declaration(%StateNode{kind: :parallel} = node, def_, level) do
    block(node, render_parallel_body(node, def_, level + 1), level)
  end

  defp declaration(%StateNode{kind: :region} = node, def_, level) do
    block(node, render_compound_body(node, def_, level + 1), level)
  end

  defp block(%StateNode{id: id}, body, level) do
    [indent(level, "state #{name(id)} {")] ++ body ++ [indent(level, "}")]
  end

  defp initial_arrow(%StateNode{initial: nil}, _level), do: []

  defp initial_arrow(%StateNode{initial: id}, level) do
    [indent(level, "[*] --> #{name(id)}")]
  end

  # ── Transitions ──────────────────────────────────────────────────────────

  defp render_transitions(%StateNode{transitions: ts, id: source_id}, def_, level) do
    Enum.map(ts, fn t -> render_transition(source_id, t, def_, level) end)
  end

  defp render_transition(source_id, transition, def_, level) do
    target_label = target_repr(transition.target, def_)
    label = transition_label(transition)

    line =
      case label do
        "" -> "#{name(source_id)} --> #{target_label}"
        _ -> "#{name(source_id)} --> #{target_label}: #{label}"
      end

    indent(level, line)
  end

  defp target_repr(nil, _def_), do: "[*]"

  defp target_repr(target_id, def_) do
    case Definition.fetch!(def_, target_id).kind do
      :final -> "[*]"
      _ -> name(target_id)
    end
  end

  defp transition_label(t) do
    [
      if(t.event, do: Atom.to_string(t.event), else: nil),
      if(t.guard, do: "[guard]", else: nil),
      if(t.action, do: "/action", else: nil),
      if(t.type == :internal, do: "(internal)", else: nil)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp indent(level, content), do: String.duplicate(@indent_unit, level) <> content

  defp name(id), do: id |> Atom.to_string() |> escape()

  defp escape(name) do
    if String.match?(name, ~r/^[A-Za-z_][A-Za-z0-9_]*$/) do
      name
    else
      "\"" <> String.replace(name, "\"", "'") <> "\""
    end
  end
end
