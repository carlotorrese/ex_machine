---
name: Bug report
about: Create a report to help us improve ExMachine
title: "[BUG] "
labels: bug
assignees: ""
---

**Describe the bug**
A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:

1. Define state machine with '...'
2. Execute transition '...'
3. Call function '...'
4. See error

**Expected behavior**
A clear and concise description of what you expected to happen.

**Code Example**

```elixir
# Please provide a minimal code example that reproduces the issue
defmodule MyStateMachine do
  use ExMachine.Statechart

  def definition do
    # Your state machine definition here
  end
end
```

**Environment (please complete the following information):**

- Elixir version: [e.g. 1.16.1]
- Erlang/OTP version: [e.g. 26.2.2]
- ExMachine version: [e.g. 0.1.0]
- OS: [e.g. macOS, Ubuntu]

**Additional context**
Add any other context about the problem here, including:

- Error messages
- Stack traces
- Log output
