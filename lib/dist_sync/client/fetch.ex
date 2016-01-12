defmodule DistSync.Client.Fetch do
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

      {:kill_signal, reason} ->
        IO.puts "Fetch thread got kill signal: '#{reason}'"
        :ok
    end
  end

  defp handle_fetch_update_all(dir, all_digests) do
    digest_list = Map.to_list all_digests
    update_all_files dir, digest_list
  end

  defp update_all_files(_, []) do end
  defp update_all_files(dir, [{filename, {server_mtime, compressed_contents}} | rest]) do
    full_filename = dir <> "/" <> filename
    exists = File.exists? full_filename
    local_mtime = DistSync.Client.Utils.get_file_mtime full_filename

    case (not exists) or (local_mtime < server_mtime) do
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
    File.write! dir <> "/" <> filename, (DistSync.Client.Utils.decompress compressed_contents)
  end
end
