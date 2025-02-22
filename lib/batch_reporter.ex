defmodule TelemetryInfluxDB.BatchReporter do
  @moduledoc """
  This module handles batching events to be reported to Influx. It will call the provided
  report function with any events that have been enqueued since the last report. If a batch_time
  is not provided, delay between batches will default to 0, which will send all
  enqueued events immediately.
  """

  use GenServer

  defmodule State do
    defstruct [:report_fn, :batch_time, report_scheduled?: false, unreported_events: []]

    def enqueue_event(state, event) do
      %{state | unreported_events: [event | state.unreported_events]}
    end

    def set_unreported_events(state, remaining_events) do
      %{state | unreported_events: remaining_events}
    end

    def set_report_scheduled(state) do
      %{state | report_scheduled?: true}
    end

    def reset_report_scheduled(state) do
      %{state | report_scheduled?: false}
    end
  end

  def start_link(opts \\ []) do
    {report_fn, opts} = Keyword.pop(opts, :report_fn)
    {batch_time, opts} = Keyword.pop(opts, :batch_time, 0)

    state = %State{
      report_fn: report_fn,
      batch_time: batch_time
    }

    GenServer.start_link(__MODULE__, state, opts)
  end

  def init(state) do
    {:ok, state}
  end

  def enqueue_event(pid \\ __MODULE__, event) do
    GenServer.cast(pid, {:enqueue_event, event})
  end

  def handle_cast({:enqueue_event, event}, state) do
    updated_state =
      state
      |> State.enqueue_event(event)
      |> maybe_report_events()

    {:noreply, updated_state}
  end

  def handle_info(:report_events, state) do
    state.report_fn.(Enum.reverse(state.unreported_events))

    updated_state =
      state
      |> State.set_unreported_events([])
      |> State.reset_report_scheduled()

    {:noreply, updated_state}
  end

  def get_name(config) do
    :erlang.binary_to_atom(config.reporter_name <> "_batch_reporter", :utf8)
  end

  defp maybe_report_events(%{report_scheduled?: true} = state), do: state

  defp maybe_report_events(%{unreported_events: []} = state), do: state

  defp maybe_report_events(state) do
    if state.batch_time > 0 do
      Process.send_after(self(), :report_events, state.batch_time)
    else
      send(self(), :report_events)
    end
    State.set_report_scheduled(state)
  end
end
