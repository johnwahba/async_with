defmodule AsyncWith do
  defmacro async({:with, _meta, lines}) do
    with_matches = lines
    |> Enum.slice(0..-2)
    |> Enum.with_index

    start_futures = Enum.map(with_matches, &to_future(&1, with_matches))
    blocking_futures = generate_dependency_withs_for(with_matches, :include_all)
    last_line = [List.last(lines)]

    new_with = Enum.concat([blocking_futures, last_line])
    result_var = Macro.var(:"result", __MODULE__)

    quote do
      unquote_splicing(start_futures)
      unquote(result_var) = try do
        with unquote_splicing(new_with)
      after
        unquote_splicing(clean_futures(with_matches))
      end
      unquote(result_var)
    end
  end

  def to_future({_, idx} = line, with_matches)  do
    dependencies = generate_dependency_withs_for(with_matches, line)
    future_body = case line do
      {{op,_,[_,right]}, _} when op in [:<-, :=] -> right
      {body, _} -> body
    end

    quote do
      unquote(future_var(idx)) = Future.new(fn() ->
          with unquote_splicing(dependencies) do
            unquote(future_body)
          end
      end)
    end
  end

  def clean_futures(with_matches) do
    started_futures = with_matches
    |> Enum.map(fn({_,idx}) -> future_var(idx) end)
    quote do
      Enum.each((unquote(started_futures)), &Future.shutdown/1)
    end
    |> List.wrap
  end

  def generate_dependency_withs_for(lines, line) do
    lines
    |> Enum.reduce_while([], &accumulate_dependencies(line, &1, &2))
    |> Enum.map(&assign_to_future_value/1)
  end

  def accumulate_dependencies(line, potential_dependency, accum)
  def accumulate_dependencies({line, idx}, {line, idx}, accum), do: {:halt, accum}
  def accumulate_dependencies(:include_all, {potential_dependency, idx}, accum) do
    {:cont, [{potential_dependency, idx} | accum]}
  end
  def accumulate_dependencies({line, _line_idx}, {potential_dependency, idx}, accum) do
    if is_dependency_for?(potential_dependency, line) do
      {:cont, [{potential_dependency, idx} | accum]}
    else
      {:cont, accum}
    end
  end

  def is_dependency_for?(potential_dependency, line) do
    assignments = var_assignments(potential_dependency)
    requirements =  var_requirements(line)
    !MapSet.disjoint?(assignments, requirements)
  end

  def var_assignments({op, _, [left, _]}) when op in [:<-, :=] do
    extract_vars(left)
  end
  def var_assignments(_) do
    MapSet.new()
  end


  def var_requirements({:<-, _, [_, right]}) do
    extract_vars(right)
  end
  def var_requirements(resp) do
    extract_vars(resp)
  end

  def extract_vars(ast) do
    {_, vars} = Macro.postwalk(ast, [], fn
        ({var, _, nil}, acc) when is_atom(var) -> {:ok, [var | acc]}
        (_, acc) -> {:ok, acc}
      end)
    MapSet.new(vars)
  end

  def assign_to_future_value({{op, meta, [left, _]}, _idx} = line) when op in [:<-, :=] do
    {op, meta, [left, future_value_for(line)]}
  end
  def assign_to_future_value(line) do
    future_value_for(line)
  end

  def future_value_for({_, idx}) do
    quote do
      Future.value(unquote(future_var(idx)))
    end
  end

  def future_var(idx) do
    Macro.var(:"future_#{idx}", __MODULE__)
  end
end
