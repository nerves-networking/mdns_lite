defmodule MdnsLiteTest do
  use ExUnit.Case
  doctest MdnsLite

  test "greets the world" do
    assert MdnsLite.hello() == :world
  end
end
