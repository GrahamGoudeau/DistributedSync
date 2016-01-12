defmodule DistSync.Client.Serve do

  # a serving thread must be created with a corresponding fetching thread
  def setup_serve(directory, fetch_thread, server) do
    files = DistSync.Client.Utils.get_files directory
    file_digests_map = build_digests_map files
    serve_update_files files, fetch_thread, server
    serve_loop directory, files, file_digests_map, fetch_thread, server
  end

  defp serve_loop(dir, files, file_digests_map, fetch_thread, server) do
    new_files_list = DistSync.Client.Utils.get_files dir
    new_digests = build_digests_map new_files_list

    updated_files = for file <- new_files_list,
                      Map.get(new_digests, file, nil) != Map.get(file_digests_map, file, nil),
                      do: file

    deleted_files = files -- new_files_list

    serve_update_files updated_files, fetch_thread, server
    serve_delete_files deleted_files, fetch_thread, server

    receive do
      {:kill_signal, reason} ->
        IO.puts "Serve thread got kill signal: '#{reason}'"
        :ok
    after
      0 -> serve_loop dir, new_files_list, new_digests, fetch_thread, server
    end
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

  defp serve_delete_file(file, fetch_thread, server) do
    IO.puts "Serving DELETE from " <> file

    basename = Path.basename file
    DistSync.Client.server_cast {:delete, basename, [fetch_thread]}, server
  end

  defp serve_delete_files(files, fetch_thread, server) do
    map_delete = &(serve_delete_file &1, fetch_thread, server)
    Enum.map files, map_delete
  end

  defp serve_update_files(files, fetch_thread, server) do
    map_serve = &(serve_update_file &1, fetch_thread, server)
    Enum.map files, map_serve
  end

  defp serve_update_file(file, fetch_thread, server) do
    IO.puts "Serving UPDATE from " <> file

    basename = Path.basename file
    time = DistSync.Client.Utils.get_file_mtime file

    case File.read file do
      {:ok, contents} ->
        updated_digest = {time, DistSync.Client.Utils.compress(contents)}
        message = {:update, basename, updated_digest, [fetch_thread]}
        DistSync.Client.server_cast message, server
      {:error, reason} -> reason
    end
  end
end
