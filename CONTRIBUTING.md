# Contributing to ExMachine

Thank you for your interest in contributing to ExMachine! 🎉

## Project Status

ExMachine is currently in **alpha stage**. We're actively working on stabilizing the API and welcome community feedback and contributions.

## How to Contribute

### Reporting Issues

- Use the [GitHub issue tracker](https://github.com/carlotorrese/ex_machine/issues)
- Search existing issues before creating a new one
- Use the provided issue templates for bug reports and feature requests
- Include as much detail as possible (Elixir version, OS, code examples)

### Submitting Changes

1. **Fork** the repository
2. **Create a feature branch** from `main`
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes** with clear, descriptive commits
4. **Add tests** for new functionality
5. **Run the test suite** to ensure nothing breaks
   ```bash
   mix test
   mix format --check-formatted
   mix dialyzer
   ```
6. **Update documentation** if needed
7. **Submit a pull request** with a clear description

### Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/carlotorrese/ex_machine.git
   cd ex_machine
   ```

2. Install dependencies:
   ```bash
   mix deps.get
   ```

3. Run tests:
   ```bash
   mix test
   ```

4. Generate documentation:
   ```bash
   mix docs
   ```

### Code Style

- Follow standard Elixir formatting (`mix format`)
- Write clear, descriptive function and variable names
- Add documentation for public functions
- Include typespecs where appropriate
- Keep functions small and focused

### Testing

- All new code should include tests
- Aim for good test coverage
- Use descriptive test names
- Test both happy path and edge cases

### Documentation

- Update documentation for any API changes
- Include code examples in module docs
- Keep README.md up to date
- Add entries to CHANGELOG.md for significant changes

## Code of Conduct

This project follows the [Hex Code of Conduct](https://hex.pm/policies/codeofconduct). Please be respectful and inclusive in all interactions.

## Questions?

Feel free to open an issue for questions or discussion about the project direction, API design, or implementation details.

## License

By contributing to ExMachine, you agree that your contributions will be licensed under the MIT License.
