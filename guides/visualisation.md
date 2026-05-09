# Visualisation

`ExMachine.Visualize` turns an `ExMachine.Definition` (or a statechart
module) into a string. Two backends:

- `to_mermaid/2` → Mermaid `stateDiagram-v2`. Paste into
  [mermaid.live](https://mermaid.live), GitHub Markdown, or any
  Mermaid-aware renderer.
- `to_scxml/2` → W3C SCXML XML. Feed to tools like
  [statechart.io](https://statechart.io) or W3C reference
  implementations.

Both renderers are **read-only**: no engine, no server, no side
effects. Safe to call at compile time.

## Mermaid

```elixir
ExMachine.Visualize.to_mermaid(TrafficLight)
#=>
# stateDiagram-v2
#   [*] --> red
#   red --> green: timer
#   green --> yellow: timer
#   yellow --> red: timer
```

Mapping highlights:

- compound → `state Name { ... }` block, `[*] --> initial` inside.
- parallel → `state Name { ... }` containing each region's block
  separated by `--`.
- final → `[*]` arrow target (no declaration).
- history → `state H <<history>>`.
- choice → `state C <<choice>>`.
- transition → `Source --> Target: event`, eventless without label.

Transitions on a compound are emitted at its **parent's** indent
level (Mermaid would otherwise nest the source inside itself).

## SCXML

```elixir
ExMachine.Visualize.to_scxml(Workflow)
#=>
# <?xml version="1.0" encoding="UTF-8"?>
# <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0" initial="running" name="workflow">
#   <state id="running" initial="work">
#     <parallel id="work">
#       <state id="left" initial="la">
#         <state id="la">
#           <transition event="finish_a" target="a_done"/>
#         </state>
#         <final id="a_done"/>
#       </state>
#       ...
#     </parallel>
#     <transition event="abort" target="aborted"/>
#     <transition event="done.state.work" target="completed"/>
#   </state>
#   ...
# </scxml>
```

Mapping highlights:

- regions render as plain `<state>` children of `<parallel>` — SCXML
  has no `<region>` tag.
- final → `<final id="..."/>`.
- history → `<history id="..." type="shallow|deep">` with a
  `<transition target="default"/>` if a default is declared.
- choice → emitted as a comment. SCXML expresses the same intent
  with multiple guarded `<transition cond="...">` on the source;
  translate by hand if you need a lossless round-trip.

## Why no graphviz / dot

Mermaid covers the modern Markdown / web rendering case; SCXML
covers the formal interop case. Adding a third format would be
busywork — open an issue if you have a concrete use case for it.
