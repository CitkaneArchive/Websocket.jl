# Websocket 
[![Build Status](https://travis-ci.org/citkane/Websocket.jl.svg?branch=master)](https://travis-ci.org/citkane/Websocket.jl)
[![Coverage Status](https://coveralls.io/repos/github/citkane/Websocket.jl/badge.svg?branch=master)](https://coveralls.io/github/citkane/Websocket.jl?branch=master)

A flexible, powerful, high level interface for Websockets in Julia. Provides a SERVER and CLIENT.

[DOCUMENTATION](https://juliahub.com/docs/Websocket)
## Basic usage server:

```julia
using Websocket

server = WebsocketServer()
ended = Condition() 

listen(server, :client, client -> (
    listen(client, :message, message -> (
        begin
            @info "Got a message" client = client.id message = message
            send(client, "Echo back at you: $message")
        end
    ))
))
listen(server, :connectError, err -> (
    begin
        logWSerror(err)
        notify(ended, err.msg, error = true)
    end    
))
listen(server, :closed, details -> (
    begin
        @warn "Server has closed" details...
        notify(ended)
    end
))

@async serve(server; verbose = true)
wait(ended)
```
## Basic usage client:

```julia
using Websocket

client = WebsocketClient()
ended = Condition()

listen(client, :connect, ws -> (
    begin
        listen(ws, :message, message -> (
            @info message
        ))
        listen(ws, :close, reason -> (
            begin
                @warn "Websocket connection closed" reason...
                notify(ended)
            end
        ))
        for count = 1:10
            send(ws, "hello $count")
            sleep(1)
        end
        close(ws)
    end
))
listen(client, :connectError, err -> (
    begin
        logWSerror(err)
        notify(ended, err.msg, error = true)
    end
))

@async open(client, "ws://localhost:8080")
wait(ended)
```
