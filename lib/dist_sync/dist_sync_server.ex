defmodule DistSync.Server do
  use GenServer

  @server_name :DistSyncServer

  def init(args) do
    {:ok, args}
  end

  def handle_cast({:unsync, subscriber}, state) do
    set_removed_sub = Map.get(state, :subscribers) |> MapSet.delete subscriber
    {:noreply, Map.put(state, :subscribers, set_removed_sub)}
  end

  # expects digest: {time_modified, compressed_contents}
  # where time_modified is in seconds
  def handle_cast({:update, filename, digest, skip_pids}, state) do
    {time_modified, _} = digest
    updated_state = case needs_global_update? state, filename, time_modified do
      true -> perform_update filename, digest, skip_pids, state
      _ -> state
    end
    {:noreply, updated_state}
  end

  def handle_cast({:delete, filename, skip_pids}, state) do
    recipients = get_fetch_threads(state) -- skip_pids
    broadcast recipients, {:delete, filename}
    removed_digest_map = get_file_digests(state) |> Map.delete filename

    updated_state = Map.update! state, :file_digests, fn _ -> removed_digest_map end
    {:noreply, updated_state}
  end

  def handle_cast(_, state) do
    {:noreply, state}
  end

  def handle_call({:get_time}, _from, state) do
    {:reply, {:server_time, :os.system_time}, state}
  end

  def handle_call({:sync, {fetch_pid, serve_pid}}, _from, state) do
    new_id = (Map.get state, :sync_id)

    # update the subscribers
    set_added_sync = Map.get(state, :subscribers) |> MapSet.put {new_id, fetch_pid, serve_pid}

    # update the state with new subscribers set and new ID value
    updated_state = state |> (Map.put :subscribers, set_added_sync)

    {:reply, {:update_all, get_file_digests(state)}, updated_state}
  end

  def handle_call({:refresh_all}, _from, state) do
    {:reply, get_file_digests(state)}
  end

  def start_link() do
    init_state = %{file_digests: %{}, subscribers: %MapSet{}, sync_id: 0}
    GenServer.start_link(__MODULE__, init_state, name: @server_name)
  end

  defp perform_update(filename, digest, skip_pids, state) do
    # only serve the changes to the directories OTHER than where the change originated from
    recipients = get_fetch_threads(state) -- skip_pids

    {time_modified, compressed_contents} = digest

    # send the compressed file contents to those fetch threads
    broadcast recipients, {:update, filename, compressed_contents}

    updated_digests = get_file_digests(state) |> Map.put filename, {time_modified, compressed_contents}

    # update the state to reflect the changes
    Map.update! state, :file_digests, fn _ -> updated_digests end
  end

  defp needs_global_update?(state, filename, time_modified) do
    # perform an update if file is new, or if it was modified after we stored it
    case get_file_digest state, filename do
      nil -> true
      {stored_time, _} -> stored_time < time_modified
    end
  end

  defp get_fetch_threads(state) do
    for {_, fetch, _} <- get_subscribers_list(state), do: fetch
  end

  defp get_subscribers_list(state) do
    state |> Map.get(:subscribers) |> MapSet.to_list
  end

  defp get_file_digest(state, filename) do
    state |> get_file_digests |> Map.get filename
  end

  defp get_file_digests(state) do
    state |> Map.get :file_digests
  end

  defp broadcast([], _) do end
  defp broadcast([to | rest], message) do
    send to, message
    broadcast rest, message
  end
end
