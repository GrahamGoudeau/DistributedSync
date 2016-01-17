# DistSync

DistributedSync allows for distributed filesystem synchronization.  Each directory is synchronized using an instance of a `DistSync.Client`, which communicates any changes that occur to the main server `DistSync.Server`.  The `DistSync.Server` is responsible for relaying those changes on to all the clients that have "subscribed" to the synchronization.  In this way, each individual client can avoid having to know about any other client that exists.

A "client" actually consists of several threads: 
 * a "serve" thread, which tracks which files have been added, changed, or deleted; 
 * a "fetch" thread, which watches for messages from the server and modifies files accordingly;
 * a directory monitor thread, which kills the client if the directory is deleted or not present
 * a server monitor thread, which kills the client if the server goes offline

## Challenges Faced
 * Avoiding infinite loops
    * For example: a file in `directoryA` is updated; that update is sent to the server; the server sends a message to `directoryA` telling it to update that same file; the client sees that the file was updated AGAIN, and sends another update to the server, etc.
 * Resolving filename clashes
    * For example: `directoryA` and `directoryB` both contain file `example.txt`.  `directoryA` is synced first, and the server stores the contents of `directoryA/example.txt`.  Then `directoryB` is synced, and new contents under the name `example.txt` are sent to the server.
    
* Avoiding sending the entire contents of a file through Elixir's message passing system

## Challenges Resolved
* Infinite loops were avoided by having the client's serve threads be aware of their corresponding fetch threads.  They include that fetch thread's PID in messages to the server, so that the server can relay the changes to all the listening fetch threads EXCEPT that one.
* Filename clashes are resolved by always taking the most recent changes as the point of truth.  This implies that the following would occur:
    * `directoryA` contains `example.txt`, last modified at 3:00pm.
    * `directoryB` contains `example.txt`, last modified at 3:30pm.
    * `directoryA` is synced at 4:00pm, and the server considers the contents of `directoryA/example.txt` to be the point of truth for `example.txt`.
    * `directoryB` is synced at 4:05pm, and the server now considers the contents of `directoryB/example.txt` to be the point of truth for `example.txt`, and the proper update messages are sent out to the listening fetch threads.
    * `directoryA/example.txt` now mirrors `directoryB/example.txt`
* Because Elixir's actor message passing system works best when the messages are small, the contents of an updated file are first compressed using `:zlib.zip/1` and `:zlib.unzip/1` from Erlang's `zlib` module.  The clients are responsible for compressing and decompressing messages that are sent and received, respectively.

***

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
