struct WebsocketServer
    config::NamedTuple
    callbacks::Dict{Symbol, Union{Bool, Function}}
    flags::Dict{Symbol, Bool}
    sockets::Array{WebsocketConnection, 1}

    function WebsocketServer(; config...)
        @debug "WebsocketClient"
        config = merge(serverConfig, (; config...), (; maskOutgoingPackets = false, type = "server",))
        self = new(
            config,
            Dict{Symbol, Union{Bool, Function}}(
                :client => false,
                :connectError => false,
            ),
            Dict{Symbol, Bool}(
                :isopen => false
            ),
            []
        )
    end

end
function listen(
    self::WebsocketServer,
    key::Symbol,
    cb::Function
)
    if haskey(self.callbacks, key) && !(self.callbacks[key] isa Function)
        self.callbacks[key] = data -> (
            @async try
                cb(data)
            catch err
                err = CallbackError(err, catch_backtrace())
                err.log()
                exit()
            end
        )
    end
end

function validateUpgrade(headers::HTTP.Messages.Request)
    if !HTTP.hasheader(headers, "Upgrade", "websocket")
        throw(error("""did not receive "Upgrade: websocket" """))
    end
    if !HTTP.hasheader(headers, "Connection", "Upgrade") || HTTP.hasheader(headers, "Connection", "keep-alive upgrade")
        throw(error("""did not receive "Connection: Upgrade" """))
    end
    if !HTTP.hasheader(headers, "Sec-WebSocket-Version", "13") && !HTTP.hasheader(headers, "Sec-WebSocket-Version", "8")
        throw(error("""did not receive "Sec-WebSocket-Version: [13 or 8]" """))
    end
    if !HTTP.hasheader(headers, "Sec-WebSocket-Key")
        throw(error("""did not receive "Sec-WebSocket-Key" header."""))
    end
end

function serve(self::WebsocketServer, port::Int = 8080, host = "localhost"; options...)
    @debug "WebsocketServer.listen"
    config = self.config
    options = merge(serverOptions, (; options...))

    try
        host = getaddrinfo(host)
        if config.ssl
            tlsconfig = HTTP.Servers.SSLConfig(config.sslcert, config.sslkey)
            options = merge(options, (; sslconfig = tlsconfig))
        end
        callback = self.callbacks[:client]
        callback === false && throw(error("tried to bind the server before registering \":client\" handler"))

        HTTP.listen(host, port; options...) do io
            tcp = io.stream.c.io isa TCPSocket ? io.stream.c.io : io.stream.c.io.bio
            Sockets.nagle(tcp, config.useNagleAlgorithm)
            try
                headers = io.message
                validateUpgrade(headers)
                HTTP.setstatus(io, 101)
                key = string(HTTP.header(headers, "Sec-WebSocket-Key"))
                HTTP.setheader(io, "Sec-WebSocket-Accept" => acceptHash(key))
                HTTP.setheader(io, "Upgrade" => "websocket")
                HTTP.setheader(io, "Connection" => "Upgrade")

                startwrite(io)

                connection = WebsocketConnection(config, self.sockets)
                connection.io[:stream] = io.stream
                push!(self.sockets, connection)
                callback(connection)
                startConnection(connection, io)
            catch err
                @error err exception = (err, catch_backtrace())
                HTTP.setstatus(io, 400)
                startwrite(io)
            end
        end
    catch err
        err = ConnectError(err, catch_backtrace())
        callback = self.callbacks[:connectError]
        if callback isa Function
            callback(err)
        else
            err.log()
        end
    end
end

function emit(self::WebsocketServer, data::Union{Array{UInt8,1}, String, Number})
    for connection in self.sockets
        send(connection, data)
    end
end