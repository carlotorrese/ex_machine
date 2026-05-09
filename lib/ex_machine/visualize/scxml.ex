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
    open = root_open_tag(root)
    body = render_root_body(root, def_)
    Enum.join([~s(<?xml version="1.0" encoding="UTF-8"?>), open] ++ body ++ ["</scxml>"], "\n")
  end

  # The <scxml> opening tag. For a parallel root we point `initial=` at
  # the wrapping <parallel> so a conformant interpreter activates the
  # whole parallel (rather than treating the regions as a compound and
  # picking only the first).
  defp root_open_tag(%StateNode{kind: :parallel} = root) do
    ~s(<scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0") <>
      ~s( initial="#{name(root.id)}") <>
      ~s( name="#{name(root.id)}">)
  end

  defp root_open_tag(%StateNode{} = root) do
    initial_attr =
      case root.initial do
        nil -> ""
        id -> ~s( initial="#{name(id)}")
      end

    ~s(<scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0") <>
      initial_attr <> ~s( name="#{name(root.id)}">)
  end

  # ── Root body ───────────────────────────────────────────────────────────

  # Compound root: substates and root-level transitions sit directly under
  # <scxml>. Parallel root: wrap regions in <parallel id="..."> so the
  # XML is structurally valid SCXML (bug_003).
  defp render_root_body(%StateNode{kind: :parallel} = root, def_) do
    regions =
      Enum.flat_map(root.substates, fn id ->
        render_node(Definition.fetch!(def_, id), def_, 2)
      end)

    transitions = Enum.map(root.transitions, &render_transition(&1, 2))

    [indent(1, ~s(<parallel id="#{name(root.id)}">))] ++
      regions ++ transitions ++ [indent(1, "</parallel>")]
  end

  defp render_root_body(%StateNode{} = root, def_) do
    children =
      Enum.flat_map(root.substates, fn id ->
        render_node(Definition.fetch!(def_, id), def_, 1)
      end)

    transitions = Enum.map(root.transitions, &render_transition(&1, 1))
    children ++ transitions
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

  defp render_node(%StateNode{kind: :history} = node, def_, level) do
    type = Atom.to_string(node.history_type || :shallow)
    open = indent(level, ~s(<history id="#{name(node.id)}" type="#{type}">))

    # SCXML XSD requires exactly one <transition> child specifying the
    # default substate. When no `:default` is declared we fall back to
    # the parent's `:initial`, matching the engine's runtime behaviour
    # in default_restore_chain/2.
    default_target =
      node.history_default ||
        Definition.fetch!(def_, node.parent).initial

    inner = [indent(level + 1, ~s(<transition target="#{name(default_target)}"/>))]
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
        if(t.event, do: ~s( event="#{escape_attr(Atom.to_string(t.event))}"), else: nil),
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
