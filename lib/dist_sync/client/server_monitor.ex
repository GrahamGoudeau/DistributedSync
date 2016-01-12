defmodule DistSync.Client.ServerMonitor do
  def server_monitor({fetch_pid, serve_pid}, server) do
    if Process.alive?(fetch_pid) and Process.alive?(serve_pid) do
      case is_server_alive?(server) do
        false ->
          send fetch_pid, {:kill_signal, "Server down"}
          send serve_pid, {:kill_signal, "Server down"}
        true ->
          server_monitor({fetch_pid, serve_pid}, server)
      end
    end
  end

  defp is_server_alive?({:remote_server, server}) do
    case Enum.find Node.list, false, (fn(connection) -> connection == server end) do
      false -> false
      _ -> true
    end
  end

  defp is_server_alive?({:local_server, server_pid}) do
    Process.alive? server_pid
  end
end
