defmodule DistSync.Client.Utils do
  def decompress(compressed) do
    :zlib.unzip compressed
  end

  def compress(contents) do
    :zlib.zip contents
  end

  # return the contents with their full file paths
  def get_dir_contents(dir) do
    case File.ls dir do
      {:ok, content} -> Enum.map content, &(dir <> "/" <> &1)
      _ -> []
    end
  end

  def get_files(dir) do
    dir |> get_dir_contents |> Enum.filter &(not File.dir?(&1))
  end

  def get_absolute_path(dir) do
    dir |> Path.absname |> Path.expand
  end

  def get_crypto_digest(digest_contents) do
    :crypto.hash(:md5, digest_contents)
  end

  def get_file_mtime(file) do
    # get the file mtime in seconds (:posix)
    case File.stat file, [time: :posix] do
      {:ok, stat} -> stat.mtime
      {:error, reason} -> reason
    end
  end

end
