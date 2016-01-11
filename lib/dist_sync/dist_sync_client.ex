defmodule DistSync.Client do
  @server_name :DistSyncServer

  # params: string, string
  def sync(directory, server) do
    absolute_directory = get_absolute_path directory
    server_atom = String.to_atom server
    node_status = Node.connect server_atom

    if node_status == true do
      fetch_serve_pids = setup_threads absolute_directory, server_atom
      server_cast {:sync, fetch_serve_pids}, server_atom
      {:ok, fetch_serve_pids}
    else
      IO.puts "Failed to connect; reason: '#{node_status}'"
      {:error, node_status}
    end
  end

  def unsync({fetch_pid, serve_pid}) do
    send fetch_pid, :kill_signal
    send serve_pid, :kill_signal
  end

  defp is_server_alive?(server) do
    Enum.find Node.list, false, fn(connection) -> connection == server end
  end

  def server_monitor({fetch_pid, serve_pid}, server) do
    case is_server_alive?(server) do
      false ->
        send fetch_pid, :kill_signal
        send serve_pid, :kill_signal
      server ->
        server_monitor({fetch_pid, serve_pid}, server)
    end
  end

  defp setup_threads(directory, server) do
    fetch_thread = spawn_link __MODULE__, :setup_fetch, [directory]

    # tell the serve_thread the pid of the fetch thread, so that we
    # avoid serving content from this directory back to this directory
    serve_thread = spawn_link __MODULE__, :setup_serve, [directory, fetch_thread, server]

    # setup the server monitor
    spawn_link __MODULE__, :server_monitor, [{fetch_thread, serve_thread}, server]
    {fetch_thread, serve_thread}
  end

  def setup_fetch(directory) do
    fetch_loop(directory)
  end

  def fetch_loop(directory) do
    receive do
      {:update_all, all_digests} ->
        handle_fetch_update_all directory, all_digests
        fetch_loop(directory)

      {:update, filename, compressed_contents} ->
        handle_fetch_update directory, filename, compressed_contents
        fetch_loop(directory)

      {:delete, filename} ->
        handle_fetch_delete directory, filename
        fetch_loop(directory)

      :kill_signal -> :ok
    end
  end

  def setup_serve(directory, fetch_thread, server) do
    files = get_files directory
    file_digests_map = build_digests_map files
    serve_update_files files, fetch_thread, server
    serve_loop directory, files, file_digests_map, fetch_thread, server
  end

  defp decompress(compressed) do
    :zlib.unzip compressed
  end

  defp compress(contents) do
    :zlib.zip contents
  end

  defp handle_fetch_update_all(dir, all_digests) do
    digest_list = Map.to_list all_digests
    update_all_files dir, digest_list
  end

  defp update_all_files(_, []) do end
  defp update_all_files(dir, [{filename, {server_mtime, compressed_contents}} | rest]) do
    full_filename = dir <> "/" <> filename
    exists = File.exists? full_filename

    case (not exists) or (get_file_mtime full_filename) < server_mtime do 
      true -> handle_fetch_update(dir, filename, compressed_contents)
      _ -> :ok
    end

    update_all_files dir, rest
  end

  defp handle_fetch_delete(dir, filename) do
    IO.puts "Fetched DELETE for " <> filename <> " to " <> dir

    case File.rm(dir <> "/" <> filename) do
      :ok -> :ok
      {:error, reason} -> reason
    end
  end

  defp handle_fetch_update(dir, filename, compressed_contents) do
    IO.puts "Fetched UPDATE for " <> filename <> " to " <> dir
    File.write! dir <> "/" <> filename, (decompress compressed_contents)
  end

  defp serve_loop(dir, files, file_digests_map, fetch_thread, server) do
    new_files_list = get_files dir
    new_digests = build_digests_map new_files_list

    updated_files = for file <- new_files_list,
                      Map.get(new_digests, file, nil) != Map.get(file_digests_map, file, nil),
                      do: file

    deleted_files = files -- new_files_list

    serve_update_files updated_files, fetch_thread, server
    serve_delete_files deleted_files, fetch_thread, server

    receive do
      :kill_signal -> :ok
    after
      0 -> serve_loop dir, new_files_list, new_digests, fetch_thread, server
    end
  end

  defp get_dir_contents(dir) do
    # return the contents with their full file paths
    case File.ls dir do
      {:ok, content} -> Enum.map content, &(dir <> "/" <> &1)
      _ -> []
    end
  end

  defp get_files(dir) do
    dir |> get_dir_contents |> Enum.filter &(not File.dir?(&1))
  end

  defp get_absolute_path(dir) do
    dir |> Path.absname |> Path.expand
  end

  defp build_digests_map(files) do
    Enum.map(files, &({&1, get_digest(&1)})) |> Enum.into %{}
  end

  defp get_digest(file) do
    case File.read file do
      {:ok, contents} -> :crypto.hash(:md5, contents)
      _ -> nil
    end
  end

  defp server_cast(message, server) do
    GenServer.cast {@server_name, server}, message
  end

  defp server_call(message, server) do
    case is_server_alive?(server) do
      false ->
        IO.puts "WARNING -- server #{server} has gone offline"
        send self, :kill_signal
        :kill_signal
      server -> GenServer.call {@server_name, server}, message
    end
  end

  defp serve_delete_file(file, fetch_thread, server) do
    IO.puts "Serving DELETE from " <> file

    basename = Path.basename file
    server_cast {:delete, basename, [fetch_thread]}, server
  end

  defp serve_delete_files(files, fetch_thread, server) do
    map_delete = &(serve_delete_file &1, fetch_thread, server)
    Enum.map files, map_delete
  end

  defp serve_update_files(files, fetch_thread, server) do
    map_serve = &(serve_update_file &1, fetch_thread, server)
    Enum.map files, map_serve
  end

  defp get_file_mtime(file) do
    # get the file mtime in seconds (:posix)
    case File.stat file, [time: :posix] do
      {:ok, stat} -> stat.mtime
      {:error, reason} -> reason
    end
  end

  defp serve_update_file(file, fetch_thread, server) do
    IO.puts "Serving UPDATE from " <> file

    basename = Path.basename file
    time = get_file_mtime file

    case File.read file do
      {:ok, contents} ->
        updated_digest = {time, compress(contents)}
        server_cast {:update, basename, updated_digest, [fetch_thread]}, server
      {:error, reason} -> reason
    end
  end
end
