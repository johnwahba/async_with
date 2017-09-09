defmodule AsyncWithTest do
  use ExUnit.Case
  require AsyncWith
  import AsyncWith

  @doc """
  Here's what the below task expands to:
  (
    future_0 = Future.new(fn -> with() do
      1
    end end)
    future_1 = Future.new(fn -> with(x when is_integer(x) <- Future.value(future_0)) do
      x + 1
    end end)
    future_2 = Future.new(fn -> with(a <- Future.value(future_1)) do
      a + 1
    end end)
    future_3 = Future.new(fn -> with() do
      1
    end end)
    result = with(r = Future.value(future_3), b <- Future.value(future_2), a <- Future.value(future_1), x when is_integer(x) <- Future.value(future_0)) do
      {x, a, b, r}
    else
      res ->
        {:error, res}
    end
    Enum.each([future_0, future_1, future_2, future_3], &Future.shutdown/1)
    result
  )

  """
  test "happy path" do
    assert {1, 2, 3, 1} == async(with x when is_integer(x) <- 1,
      a <- x + 1,
      b <- a + 1,
      "irrelevant string",
      r = 1 do
        {x, a, b, r}
      else
        res -> {:error, res}
      end)
  end

  test "processes do not leak" do
    process_count_before = length(Process.list)
    assert {:a, :b} == async(with a <- :a, b <- :b do
        {a, b}
      end)
    :timer.sleep(1) # Wait for processes to die
    assert length(Process.list) == process_count_before
  end


  test "else works" do
    process_count_before = length(Process.list)
    assert {:error, 1} == async(with a <- :a, :b <- a, r <- 1, 2 <- r do
        IO.inspect(r)
        {a, a}
      else
        result -> {:error, result}
      end)
    :timer.sleep(1) # Wait for processes to die
    assert length(Process.list) == process_count_before
  end
end
