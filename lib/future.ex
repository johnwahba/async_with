defmodule Future do
  def new(func) do
    spawn_link(fn() ->
      func.()
      |> serve_value()
    end)
  end

  def serve_value(value) do
    receive do
      {:get_value, pid} ->
        send(pid, {:value, value})
        serve_value(value)
      :kill ->
        Process.exit(self(), :normal)
    end
  end

  def value(pid) do
    send(pid, {:get_value, self()})
    receive do
      {:value, value} -> value
    end
  end

  def shutdown(pid) do
    send(pid, :kill)
  end
end
