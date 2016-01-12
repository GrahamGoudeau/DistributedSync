defmodule DistSync.Client.DirectoryMonitor do
  def directory_monitor({fetch_thread, serve_thread}, directory) do
    error_message = {:kill_signal, "Directory '" <> directory <> "' deleted"}

    if (Process.alive? fetch_thread) and (Process.alive? serve_thread) do
      if not File.exists? directory do
        send fetch_thread, error_message
        send serve_thread, error_message
      else
        directory_monitor({fetch_thread, serve_thread}, directory)
      end
    end
  end
end
