defmodule MCTest do
  use ExUnit.Case
  doctest MC

  test "greets the world" do
    assert MC.hello() == :world
  end
end
