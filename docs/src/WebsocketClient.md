# Websocket Client

Provides a Websocket client compatible with Websocket versions [8, 13]

Currently does not support Websocket Extensions

Minimum required usage:
```julia
using Websocket

client = WebsocketClient()

listen(client, :connect) do ws::WebsocketConnection #must be called before `open`
    #...
end

open(client, "ws://url.url")
```

## Constructor
```@docs
WebsocketClient
```
## Client Methods
```@docs
Base.open(::WebsocketClient, ::String)
isopen(::WebsocketClient)
```
## Client Events
Client event callback functions are registered using the `listen` method.
```@docs
listen(::WebsocketClient, ::Symbol, ::Function)
```

