function wsclient(client, port::Int = 8080, url::String = "ws://localhost")
    ended = Condition()
    listen(client, :connectError, err -> (
        notify(ended, err)
    ))
    listen(client, :connect, ws -> (
        begin
            listen(ws, :close, reason -> (
                notify(ended, reason)
            ))
        end
    ))
    @async open(client, "$url:$port"; require_ssl_verification = false)
    wait(ended)
end

function clientconnects(client, port::Int = 8080, url::String = "ws://localhost")
    ended = Condition()
    listen(client, :connectError, err -> (
        notify(ended, err)
    ))
    listen(client, :connect, ws -> (
        begin
            listen(ws, :invalidlistener, () -> ())
            listen(ws, :close, reason -> (
                notify(ended, reason)
            ))
            close(ws)
        end
    ))
    @async open(client, "$url:$port"; require_ssl_verification = false)
    wait(ended)
end

function echoclient(client, port::Int = 8080, url::String = "ws://localhost"; config...)
    config = (; config...)
    ended = Condition()
    listen(client, :connect, ws -> (
        begin
            listen(ws, :close, reason -> (
                notify(ended, reason)
            ))
            listen(ws, :message, message -> (
                begin
                    if length(message) < config.maxReceivedMessageSize
                        mstring = message
                        !(message isa String) && (mstring = String(copy(message)))
                        if !startswith(mstring, "This") || !endswith(mstring, "test.")
                            @error "$(ws.id) : $(message isa String ? "string" : "binary") : $(length(message)) : $(Int(config.maxReceivedMessageSize))" message = message
                            throw(error("bad message format"))
                        end
                        if message isa String
                            message = message*message
                        else
                            push!(message, message...)
                        end
                        if length(message) > config.maxReceivedMessageSize
                            message = message[1:Int(config.maxReceivedMessageSize)]
                        end
                        send(ws, message)
                    elseif length(message) == config.maxReceivedMessageSize
                        close(ws)
                    else
                        throw(error("message size mismatch"))
                    end
                end
            ))
            #send(ws, "This $(ws.id) test.")
            send(ws, "This is a test.")
        end
    ))
    @async open(client, "$url:$port"; require_ssl_verification = false)
    wait(ended)
end

function badclient(client, port::Int = 8080, url::String = "ws://localhost")
    ended = Condition()
    listen(client, :connect, ws -> (
        begin
            listen(ws, :close, reason -> (
                notify(ended, reason)
            ))
            listen(ws, :message, message -> (
                begin
                    message = message*message
                    send(ws, message)
                end
            ))
            send(ws, "This is a test.")
        end
    ))
    @async open(client, "$url:$port"; require_ssl_verification = false)
    wait(ended)
end

function timeoutclient(client, port::Int = 8080, url::String = "ws://localhost")
    ended = Condition()
    listen(client, :connect, ws -> (
        begin
            listen(ws, :close, reason -> (
                notify(ended, reason)
            ))
            ws.keepalive[:pingmessage] = "death"
        end
    ))
    @async open(client, "$url:$port"; require_ssl_verification = false)
    wait(ended)
end

function pingclient(client, port::Int = 8080, url::String = "ws://localhost")
    ended = Condition()
    listen(client, :connect, ws -> (
        begin
            listen(ws, :pong, message -> (
                close(ws, 1000, message)
            ))
            listen(ws, :close, reason -> (
                notify(ended, reason.description)
            ))
            ping(ws, "testping")
        end
    ))
    @async open(client, "$url:$port"; require_ssl_verification = false)
    wait(ended)
end
