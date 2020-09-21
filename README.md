# Websocket

```julia
using Websocket

client = WebsocketClient()
client.on(:connect, connectCb)

# Callback functions
function connectCb(ws)
    ws.on(:message, messageCb)
    ws.send("hello world")
end
function messageCb(message)
    @show message
end
# end Callback functions

#=
Non blocking application code goes here
=#

client.connect("wss://echo.websocket.org") # blocks until HTTP connection closes
```
Or stated differently

```julia
using Websocket

client = WebsocketClient()

client.on(:connect, ws -> (

    ws.on(:message, message -> (
        @show message
    ));
    ws.send("hello world")
    
))

@async try
    client.connect("wss://echo.websocket.org")
catch err
    @error "Fatal error in websocket" exception = (err, catch_backtrace())
    exit()
end

#=
Application code goes here
=#
```
## Custom options
```julia

client.connect(url::String, [customHeaders::Dict{String, String}; kwargs...])

```
Where `kwargs` are [HTTP request](https://juliaweb.github.io/HTTP.jl/stable/public_interface/#Requests-1) options.
