defmodule Debugger do
  defmacro log(expression) do
    if Application.get_env(:debugger, :log_level) == :debug do
      quote bind_quoted: [exp: expression] do
        IO.puts("===============")
        IO.inspect(exp)
        IO.puts("===============")
        exp
      end
    else
      expression
    end
  end
end
