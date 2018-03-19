defmodule ChroxyTest do
  use ExUnit.Case
  doctest Chroxy

  test "greets the world" do
    assert Chroxy.hello() == :world
  end
end
