# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0-alpha.1] - 2026-05-09

A ground-up rewrite of the library. The 0.1.x API and storage shapes
are gone; **there is no migration path**. Use a fresh dependency line
and read the new guides under `guides/`.

### Added

- DSL (`use ExMachine.Statechart`) with compile-time validation:
  `state`, `parallel`, `region`, `final`, `history`, `choice`,
  `initial`, `initial_context`, `on`, `on_entry`, `on_exit`,
  `cond_branch`, `otherwise`.
- Pure-functional engine (`ExMachine.Engine`) implementing the SCXML
  pure-execution subset:
  - atomic, compound, parallel, region, final states;
  - history pseudostates (shallow + deep) with auto-snapshot on exit
    and restore-or-default on re-entry;
  - choice pseudostates with recursive resolution and `:otherwise`
    fallback;
  - internal vs external transitions (proper LCCA handling);
  - eventless ("always") transitions, run-to-completion;
  - `done.state.<id>` events with bubble-up across parallel regions.
- Multi-transition microsteps with SCXML `remove_conflicting`
  (deeper-source wins, document-order tie-break).
- Server-mode (`use ExMachine.Server, statechart: Mod`) with
  `start_link / send_event / call_event / get_configuration /
  get_context / get_snapshot / subscribe / unsubscribe / stop`;
  graceful behaviour on terminal configurations (server stays alive,
  refuses events).
- Delayed events (`Step.send_after/4`) and invoked services
  (`Step.invoke/4`) with auto-cancellation when the owner state
  exits, plus `Step.cancel/2` for explicit cancellation.
- `:telemetry` events (`[:ex_machine, :macrostep, :start | :stop |
  :exception]`, `[:ex_machine, :transition]`,
  `[:ex_machine, :stopped]`) and an attachable
  `ExMachine.Logger.attach/1`.
- Pub/sub for snapshots via `ExMachine.PubSub` (Elixir `Registry`,
  started automatically by the library's OTP application).
- `ExMachine.Visualize.to_mermaid/2` (`stateDiagram-v2`) and
  `to_scxml/2` (W3C SCXML XML) renderers.
- Property tests over engine invariants (`test/property/`) and
  W3C-SCXML conformance scenarios (`test/scxml/`).
- Twelve topical guides under `guides/`.

### Removed

- The entire 0.1.x module surface (`ExMachine.State`, `ExMachine.Final`,
  `ExMachine.History`, `ExMachine.Context`, `ExMachine.Macrostep`,
  `ExMachine.Microstep`, `ExMachine.ServerMachine`). They are gone,
  not deprecated.

## [0.1.3] - 2025-06-09

### Added

- Comprehensive internal documentation for all ExMachine modules
- Detailed module documentation with practical examples for:
  - `ExMachine.State` - Hierarchical state definitions with best practices
  - `ExMachine.Final` - Final state usage and examples
  - `ExMachine.History` - History state types (shallow/deep) with media player example
  - `ExMachine.Context` - Context management utilities with complete API documentation
  - `ExMachine.Macrostep` - Macrostep execution tracing with debugging examples
  - `ExMachine.Microstep` - Atomic step documentation with state lifecycle details
  - `ExMachine.ServerMachine` - GenServer-based statechart execution (placeholder implementation)

### Improved

- Enhanced code examples throughout the documentation
- Better type specifications and function documentation
- Improved module organization and cross-references
- Added debugging and monitoring guidance

## [0.1.2] - 2025-06-09

### Changed

- Updated README documentation and project configuration
- Refined project settings and documentation

## [0.1.1] - 2025-06-09

### Added

- Development status indicators and badges
- Early development warning in README
- Comprehensive contributing guidelines (CONTRIBUTING.md)
- Project roadmap and current state documentation
- Alpha status indication in package description

### Changed

- Updated README with development status badges
- Enhanced documentation for contributors

## [0.1.0-alpha] - 2025-06-09

### Added

- **Alpha Release**: Initial release of ExMachine functional state machine library
- Complete implementation of Statechart-based finite state machine
- Support for hierarchical states with parent-child relationships
- Entry and exit actions for state transitions
- Transition actions with custom logic
- Guard functions for conditional transitions
- Extended state management (context)
- Internal events with run-to-completion semantics
- Final pseudostates for termination
- Comprehensive test suite with 30 tests
- Sample implementations (S0, S1, S2, Authentication)
- Complete documentation with doctests
- Modern Elixir 1.16.1 and Erlang 26.2.2 support

### Technical Details

- Purely functional implementation
- Compile-time validation of state machine definitions
- Composable state definitions across modules
- GenServer integration for process-based execution
- Macrostep and microstep execution tracking
- Full compatibility with modern Elixir ecosystem

### Dependencies

- ex_doc ~> 0.31 (documentation generation)
- dialyxir ~> 1.4 (static analysis)

[Unreleased]: https://github.com/YOUR_USERNAME/ex_machine/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/YOUR_USERNAME/ex_machine/releases/tag/v0.1.0
