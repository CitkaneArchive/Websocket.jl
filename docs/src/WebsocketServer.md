# WebsocketServer
Provides a Websocket server compatible with Websocket versions [8, 13]

Currently does not support Websocket Extensions

Minimum required usage:
```julia
using Websocket

server = WebsocketServer()

listen(server, :client) do client::WebsocketConnection #must be called before `serve`
    #...
end
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
listen(::Function, ::WebsocketServer, ::Symbol)
```