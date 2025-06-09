# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
