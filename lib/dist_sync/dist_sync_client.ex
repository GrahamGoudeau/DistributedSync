defmodule DistSync.Client do
  @server_name :DistSyncServer

  # params: string, string
  def sync(directory, server) do
    absolute_directory = get_absolute_path directory
    server_atom = String.to_atom server
    node_status = Node.connect server_atom

    if node_status == true do
      fetch_serve_pids = {fetch_pid, _} = setup_threads absolute_directory, server_atom
      sync_response = GenServer.call {@server_name, server_atom}, {:sync, fetch_serve_pids}
      send fetch_pid, sync_response
    else
      IO.puts "Failed to connect; reason: '#{node_status}'"
    end
  end

  defp setup_threads(directory, server) do
    fetch_thread = spawn_link __MODULE__, :setup_fetch, [directory]
    serve_thread = spawn_link __MODULE__, :setup_serve, [directory, server]
    {fetch_thread, serve_thread}
  end

  def setup_fetch(directory) do
    fetch_loop(directory)
  end

  def fetch_loop(directory) do
    receive do
      {:update, filename, compressed_contents} ->
        handle_fetch_update directory, filename, compressed_contents
      {:delete, filename} -> filename
    end

    fetch_loop(directory)
  end

  def setup_serve(directory, server) do
    files = get_files directory
    file_digests_map = build_digests_map files
    serve_update_files files, server
    serve_loop directory, files, file_digests_map, server
  end

  defp handle_fetch_update(dir, filename, compressed_contents) do
    IO.puts "Fetched UPDATE for " <> filename <> " to " <> dir
    File.write! dir <> "/" <> filename, (:zlib.unzip compressed_contents)
  end

  defp serve_loop(dir, files, file_digests_map, server) do
    new_files_list = get_files dir
    new_digests = build_digests_map new_files_list

    updated_files = for file <- new_files_list,
                      Map.get(new_digests, file, nil) != Map.get(file_digests_map, file, nil),
                      do: file

    deleted_files = files -- new_files_list

    serve_update_files updated_files, server
    serve_delete_files deleted_files, server
    serve_loop dir, new_files_list, new_digests, server
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

  defp serve_delete_file(file, server) do
#    IO.puts "Serving DELETE from " <> file
#    basename = Path.basename file
#    server_cast {:delete
    IO.puts "Not implemented delete yet"
  end

  defp serve_delete_files(files, server) do
    map_delete = &(serve_delete_file &1, server)
    Enum.map files, map_delete
  end

  defp serve_update_files(files, server) do
    map_serve = &(serve_update_file &1, server)
    Enum.map files, map_serve
  end

  defp serve_update_file(file, server) do
    IO.puts "Serving UPDATE from " <> file
    basename = Path.basename file
    case File.read file do
      {:ok, contents} -> server_cast {:update, self, basename, :zlib.zip(contents)}, server
      _ -> :deleted
    end
  end
end
