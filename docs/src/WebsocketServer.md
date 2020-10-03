# WebsocketServer
Provides a Websocket server compatible with Websocket versions [8, 13]

Currently does not support Websocket Extensions

Minimum required usage:
```julia
using Websocket

server = WebsocketServer()

listen(server, :client, client::WebsocketConnection -> ()) #must be called before `serve`

serve(server)
```

## Constructor
```@docs
WebsocketServer
```
## Server Methods
```@docs
serve
emit
close(::WebsocketServer)
isopen(::WebsocketServer)
length(::WebsocketServer)
```
## Server Events
Server event callback functions are registered using the `listen` method.
```@docs
listen(::WebsocketServer, ::Symbol, ::Function)
```