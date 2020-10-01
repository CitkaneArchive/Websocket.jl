function servercanlisten(server::WebsocketServer, port::Int = 8080)
    ended = Condition()

    listen(server, :connectError,  err -> (
        notify(ended, err.msg)
    ))
    listen(server, :listening, detail -> (
        close(server)
    ))
    listen(server, :client, () -> ())
    listen(server, :closed, detail -> (
        notify(ended, detail)
    ))

    @async serve(server, port)

    wait(ended)
end

function echoserver(server::WebsocketServer, port::Int = 8080)
    started = Condition()

    listen(server, :client, ws -> (
        listen(ws, :message, message -> (
            send(ws, message)
        ))
    ))
    listen(server, :listening, detail -> (
        notify(started, server)
    ))

    @async serve(server, port)

    wait(started)
end
