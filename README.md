# Websocket

## Basic usage server:

```julia
using Websocket
ended = Condition() 

server = WebsocketServer(; ssl = true)

listen(server, :connectError, err -> (
    begin
        logWSerror(err)
        notify(ended, err.msg, error = true)
    end    
))

listen(server, :client, ws -> (
    begin
        broadcast(ws, "A new connection id: $(ws.id) has joined.")
        emit(server, "There are now $(length(server.sockets)) connections on the server.")
        
        listen(ws, :message, message -> (
            begin
                @info "Got a message" socket = ws.id message = message
                send(ws, "Echo back at you: $message")
            end
        ))

        listen(ws, :close, reason -> (
            begin
                broadcast(ws, "$(ws.id) left the building because: $(reason.description)")
                emit(server, "There are now $(length(server.sockets)) connections on the server.")
            end
        ))
    end
))

@async serve(server, 8080, "localhost"; verbose = true)
wait(ended)
```
## Basic usage client:

```julia
using Websocket
ended = Condition()

url = "wss://localhost:8080"
client = WebsocketClient()

listen(client, :connectError, err -> (
    begin
        logWSerror(err)
        notify(ended, err.msg, error = true)
    end    
))

listen(client, :connect, ws -> (
    begin
        println("Websocket client connected to $url")

        ping(ws, "Hello world!")

        listen(ws, :error, err -> (
            logWSerror(err)
        ))

        listen(ws, :message, message -> (
            @info message
        ))

        listen(ws, :pong, message -> (
            @info "Received a PONG" message = message
        ))

        listen(ws, :close, reason -> (
            begin
                @warn "Websocket connection is $(isopen(client) ? "OPEN" : "CLOSED")." (;
                    code = reason.code,
                    description = reason.description,
                )...
                notify(ended)
            end
        ))

        count = 0
        Timer(timer -> (
            begin
                count += 1
                send(ws, "hello $count")
                count > 10 && close(ws)
            end
        ), 0; interval = 5)
    end
))

@async open(client, url; require_ssl_verification = false)
wait(ended)
```
