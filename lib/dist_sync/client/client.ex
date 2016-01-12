defmodule DistSync.Client do
  @server_name :DistSyncServer

  # sync/1 used if the server is running on the local node
  def sync(directory) do
    case Process.whereis @server_name do
      nil ->
        reason = "#{@server_name} is not running locally"
        IO.puts reason
        {:error, reason}
      server_pid ->
        complete_sync directory, {:local_server, server_pid}
    end
  end

  # params: string, string
  def sync(directory, server) do
    server_atom = String.to_atom server

    if server_atom != :nonode@nohost and server_atom == Node.self do
      sync directory
    else
      case connect_to_node server_atom do
        :ok -> complete_sync directory, {:remote_server, server_atom}
        reason ->
          IO.puts "Failed to connect to '#{server}'; reason: '#{reason}'"
          {:error, reason}
      end
    end
  end

  def unsync({fetch_pid, serve_pid}) do
    send fetch_pid, {:kill_signal, "Unsynced"}
    send serve_pid, {:kill_signal, "Unsynced"}
  end

  def server_cast(message, {:local_server, _}) do
    GenServer.cast @server_name, message
  end

  def server_cast(message, {:remote_server, server}) do
    GenServer.cast {@server_name, server}, message
  end

  defp connect_to_node(server_atom) do
    case Node.connect server_atom do
      true -> :ok
      _ ->
        if not Node.alive? do
          "Local node not alive"
        else
          "Could not find node"
        end
    end
  end

  defp complete_sync(directory, server) do
    absolute_directory = DistSync.Client.Utils.get_absolute_path directory
    fetch_serve_pids = setup_threads absolute_directory, server
    server_cast {:sync, fetch_serve_pids}, server
    {:ok, fetch_serve_pids}
  end

  defp setup_threads(directory, server) do
    fetch_thread = spawn_link DistSync.Client.Fetch, :setup_fetch, [directory]

    # tell the serve_thread the pid of the fetch thread, so that we
    # avoid serving content from this directory back to this directory
    serve_thread = spawn_link DistSync.Client.Serve, :setup_serve, [directory, fetch_thread, server]

    # setup the server monitor
    spawn_link DistSync.Client.ServerMonitor, :server_monitor, [{fetch_thread, serve_thread}, server]

    # setup the directory monitor (kills the threads if the directory is deleted
    spawn_link DistSync.Client.DirectoryMonitor, :directory_monitor, [{fetch_thread, serve_thread}, directory]
    {fetch_thread, serve_thread}
  end
end
