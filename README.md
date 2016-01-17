# DistSync

## Compiling

Use mix:

    $ mix compile

## Usage

`DistSync` allows for distributed syncing of directories.  First, the server must be started from within an `iex` session:

    $ iex --sname server --cookie cookie_string -S mix
    iex(server@machine1)1> DistSync.Server.start_link
    {:ok, #PID<0.example.0>}
    
  Once the server has started, the client can be started.  This does not have to be on the same node, or even on the same computer on the network:

    $ iex --sname client --cookie cookie_string -S mix
    iex(client@machine2)1> DistSync.Client.sync("dirA/", "server@machine1")
    {:ok, {#PID<0.example1.0>, #PID<0.example2.0>}}
