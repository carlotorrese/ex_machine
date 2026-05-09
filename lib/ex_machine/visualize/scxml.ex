defmodule ExMachine.Visualize.Scxml do
  @moduledoc """
  Render an `ExMachine.Definition` to W3C SCXML XML
  ([spec](https://www.w3.org/TR/scxml/)).

  ## Mapping

    * **root** — the outermost `<scxml>` element with `initial=` set
      to the root's `:initial` substate (or, for a parallel root, the
      list of region ids).
    * **atomic / compound** — `<state id="..." [initial="..."]>`.
    * **parallel** — `<parallel id="...">` containing a `<state>`
      per region (SCXML has no separate `region` element; regions
      are just `<state>` children of `<parallel>`).
    * **region** — same as compound: `<state id="..." initial="...">`.
    * **final** — `<final id="..."/>`.
    * **history** — `<history id="..." type="shallow|deep">` with a
      `<transition target="default"/>` if a default substate is
      declared.
    * **choice** — emitted as a comment (SCXML has no choice
      pseudostate; idiomatic SCXML uses guarded transitions on the
      source state instead).
    * **transition** — `<transition event="..." target="..."
      type="external|internal"/>`. Guards and actions are not
      surfaced (their Elixir captures cannot round-trip through XML).
  """

  alias ExMachine.{Definition, StateNode, Transition}

  @indent_unit "  "

  @doc "Render `definition` to SCXML XML source."
  @spec render(Definition.t(), keyword()) :: String.t()
  def render(%Definition{} = def_, _opts \\ []) do
    root = Definition.fetch!(def_, def_.root)

    initial_attr =
      case root.initial do
        nil -> ""
        id -> ~s( initial="#{name(id)}")
      end

    open =
      ~s(<scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0") <>
        initial_attr <> ~s( name="#{name(root.id)}">)

    body = render_root_children(root, def_, 1)

    Enum.join([~s(<?xml version="1.0" encoding="UTF-8"?>), open] ++ body ++ ["</scxml>"], "\n")
  end

  # ── Root children ────────────────────────────────────────────────────────

  defp render_root_children(%StateNode{kind: :compound} = root, def_, level) do
    Enum.flat_map(root.substates, fn id ->
      render_node(Definition.fetch!(def_, id), def_, level)
    end)
  end

  defp render_root_children(%StateNode{kind: :parallel} = root, def_, level) do
    Enum.flat_map(root.substates, fn id ->
      render_node(Definition.fetch!(def_, id), def_, level)
    end)
  end

  # ── Per-node rendering ───────────────────────────────────────────────────

  defp render_node(%StateNode{kind: :atomic} = node, _def_, level) do
    case node.transitions do
      [] ->
        [indent(level, ~s(<state id="#{name(node.id)}"/>))]

      _ ->
        open = indent(level, ~s(<state id="#{name(node.id)}">))
        ts = Enum.map(node.transitions, &render_transition(&1, level + 1))
        close = indent(level, "</state>")
        [open] ++ ts ++ [close]
    end
  end

  defp render_node(%StateNode{kind: :final} = node, _def_, level) do
    [indent(level, ~s(<final id="#{name(node.id)}"/>))]
  end

  defp render_node(%StateNode{kind: :history} = node, _def_, level) do
    type = Atom.to_string(node.history_type || :shallow)
    open = indent(level, ~s(<history id="#{name(node.id)}" type="#{type}">))

    inner =
      case node.history_default do
        nil ->
          []

        default ->
          [indent(level + 1, ~s(<transition target="#{name(default)}"/>))]
      end

    close = indent(level, "</history>")
    [open] ++ inner ++ [close]
  end

  defp render_node(%StateNode{kind: :choice} = node, _def_, level) do
    [indent(level, "<!-- choice #{name(node.id)} omitted: not part of SCXML core -->")]
  end

  defp render_node(%StateNode{kind: :compound} = node, def_, level) do
    open = indent(level, ~s(<state id="#{name(node.id)}" initial="#{name(node.initial)}">))
    body = node_body(node, def_, level + 1)
    close = indent(level, "</state>")
    [open] ++ body ++ [close]
  end

  defp render_node(%StateNode{kind: :region} = node, def_, level) do
    open = indent(level, ~s(<state id="#{name(node.id)}" initial="#{name(node.initial)}">))
    body = node_body(node, def_, level + 1)
    close = indent(level, "</state>")
    [open] ++ body ++ [close]
  end

  defp render_node(%StateNode{kind: :parallel} = node, def_, level) do
    open = indent(level, ~s(<parallel id="#{name(node.id)}">))
    body = node_body(node, def_, level + 1)
    close = indent(level, "</parallel>")
    [open] ++ body ++ [close]
  end

  # ── Body of a state / region / parallel: substates + transitions ─────────

  defp node_body(%StateNode{} = node, def_, level) do
    children =
      Enum.flat_map(node.substates, fn id ->
        render_node(Definition.fetch!(def_, id), def_, level)
      end)

    transitions = Enum.map(node.transitions, &render_transition(&1, level))
    children ++ transitions
  end

  # ── Transitions ──────────────────────────────────────────────────────────

  defp render_transition(%Transition{} = t, level) do
    attrs =
      [
        if(t.event, do: ~s( event="#{t.event}"), else: nil),
        if(t.target, do: ~s( target="#{name(t.target)}"), else: nil),
        if(t.type == :internal, do: ~s( type="internal"), else: nil)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("")

    indent(level, "<transition" <> attrs <> "/>")
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp indent(level, content), do: String.duplicate(@indent_unit, level) <> content

  defp name(id), do: id |> Atom.to_string() |> escape_attr()

  defp escape_attr(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
