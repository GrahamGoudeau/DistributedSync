defmodule DistSync.Client do
  # params: string, string
  def sync(directory, server) do
    server_atom = String.to_atom server
    node_status = Node.connect server_atom

    if node_status == true do
      fetch_serve_pids = {fetch_pid, _} = setup_threads directory
      sync_response = GenServer.call {:DistSyncServer, server_atom}, {:sync, fetch_serve_pids}
      send fetch_pid, sync_response
    else
      IO.puts "Failed to connect; reason: '#{node_status}'"
    end
  end

  defp setup_threads(directory) do
    fetch_thread = spawn_link __MODULE__, :setup_fetch, [directory]
    serve_thread = spawn_link __MODULE__, :setup_serve, [directory]
    {fetch_thread, serve_thread}
  end

  def setup_fetch(directory) do
    #IO.puts "Fetching set up for " <> directory
    receive do
      {:update, _, _} -> IO.puts "Got an update to " <> directory <> "!"
    after
      500 -> :timeout
    end
    :timer.sleep(3000)
    setup_fetch(directory)
  end

  def setup_serve(directory) do
    #IO.puts "Serving set up for " <> directory
    :timer.sleep(3000)
    setup_serve(directory)
  end

end
