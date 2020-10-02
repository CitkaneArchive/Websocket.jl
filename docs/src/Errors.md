# Error Handling

Websockets are inherently asynchronous, so error handling can be inflexible.

Websocket.jl offers the user event hooks to register callbacks and handle errors flexibly.

SEE: [Server Events](@ref), [Client Events](@ref), [Connection Events](@ref)

If no callbacks are registered, hardcoded `@info`, `@warn` and `@error` calls will provide logging feedback, 
but the parent process will remain unaffected by exceptions.


```@meta
CurrentModule = Websocket
```
## WebsocketError
```@docs
WebsocketError
```
## WebsocketError types
```@docs
ConnectError
CallbackError
FrameError
```
## Convenience methods
```@docs
logWSerror
throwWSerror
```