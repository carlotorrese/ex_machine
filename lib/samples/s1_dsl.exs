defmodule S1 do

  statechart do
    entry, do: __MODULE__.set_foo_one
    exit, do: __MODULE__.set_foo_zero
    states initial: "s11" do
      state "s11" do
        entry, do: __MODULE__.add_bar_baz
        exit, do: __MODULE__.remove_bar_baz
      end
      state "s12"
      final "end"
    end
    transitions do
      transition "a" do
        target "s2"
        action do
          %{context | foo: 2}
        end
      end
      transition "c" do
        target "s21"
        guard, do: context[:foo] == 0
      end
      transition "e", do: "end"
    end
  end

  def set_foo_one(context), do: %{context | foo: 1}
  def set_foo_zero(context), do: %{context | foo: 0}
  def set_foo_two(context), do: %{context | foo: 2}
  def check_foo_zero(context), do: context[:foo] == 0
  def add_bar_baz(context), do: Map.put(context, :bar, :baz)
  def remove_bar_baz(context), do: Map.delete(context, :bar)

end

