alias Experimental.GenStage

defmodule GenStage.Flow.Mapper do
  @moduledoc false
  use GenStage

  def init({reducer, opts}) do
    {:producer_consumer, {[], [], [], reducer}, opts}
  end

  def handle_subscribe(:producer, _, {_, ref}, {producers, consumers, done, reducer}) do
    {:automatic, {[ref | producers], consumers, [ref | done], reducer}}
  end
  def handle_subscribe(:consumer, _, {pid, ref}, {producers, consumers, done, reducer}) do
    if is_atom(reducer) do
      msg = {:producer, reducer}
      Process.send(pid, {:"$gen_consumer", {self(), ref}, {:notification, msg}}, [:noconnect])
    end
    {:automatic, {producers, [ref | consumers], done, reducer}}
  end

  def handle_cancel(_, {_, ref}, {producers, consumers, done, reducer} = state) do
    cond do
      ref in producers ->
        {done, reducer} = maybe_notify(done, reducer, ref)
        {:noreply, [], {List.delete(producers, ref), consumers, done, reducer}}
      consumers == [ref] ->
        {:stop, :normal, state}
      true ->
        {:noreply, [], {producers, List.delete(consumers, ref), done, reducer}}
    end
  end

  def handle_info({{_, ref}, {:producer, _}}, {producers, consumers, done, reducer}) do
    {done, reducer} = maybe_notify(done, reducer, ref)
    {:noreply, [], {producers, consumers, done, reducer}}
  end
  def handle_info(_msg, state) do
    {:noreply, [], state}
  end

  def handle_events(_events, _from, {_, _, _, :done} = state) do
    {:noreply, [], state}
  end
  def handle_events(events, _from, {_, _, _, reducer} = state) do
    {:noreply, Enum.reverse(Enum.reduce(events, [], reducer)), state}
  end

  defp maybe_notify(done, :done, _ref) do
    {done, :done}
  end

  defp maybe_notify(done, reducer, ref) do
    case List.delete(done, ref) do
      [] when done != [] ->
        GenStage.async_notify(self(), {:producer, :done})
        {[], :done}
      done ->
        {done, reducer}
    end
  end
end
