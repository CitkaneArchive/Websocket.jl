# Websocket Connection
A `WebsocketConnection` type is not directly constructed by the user. it can exist in two contexts:
- SERVER [`listen`](@ref listen(::WebsocketServer, ::Symbol, ::Function)) `:client` event.
- CLIENT [`listen`](@ref listen(::WebsocketClient, ::Symbol, ::Function)) `:connect` event.
Typical SERVER:
```julia
using Websocket

server = WebsocketServer()
listen(server, :client) do client::WebsocketConnection
    # do logic with the `WebsocketConnection`
end
serve(server)
```
Typical CLIENT
```julia
using Websocket

client = WebsocketClient()
listen(client, :connect) do ws::WebsocketConnection
    # do logic with the `WebsocketConnection`
end
open(client, "ws://url.url")
```
## `WebsocketConnection` Methods
```@docs
send
broadcast(::WebsocketConnection, ::Union{Array{UInt8,1}, String, Number})
ping
close(::WebsocketConnection, ::Int, ::String)
```
## `WebsocketConnection` Events
`WebsocketConnection` event callback functions are registered using the `listen` method.
```@docs
listen(::WebsocketConnection, ::Symbol, ::Function)
```