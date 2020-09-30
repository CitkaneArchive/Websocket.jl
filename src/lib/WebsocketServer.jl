struct WebsocketServer
    config::NamedTuple
    callbacks::Dict{Symbol, Union{Bool, Function}}
    flags::Dict{Symbol, Bool}
    server::Dict{Symbol, Union{Sockets.TCPServer, Array{WebsocketConnection, 1}, Nothing}}

    function WebsocketServer(; config...)
        @debug "WebsocketClient"
        config = merge(serverConfig, (; config...), (; maskOutgoingPackets = false, type = "server",))
        self = new(
            config,
            Dict{Symbol, Union{Bool, Function}}(
                :client => false,
                :connectError => false,
                :closed => false
            ),
            Dict{Symbol, Bool}(
                :isopen => false
            ),
            Dict{Symbol, Union{Sockets.TCPServer, Array{WebsocketConnection, 1}, Nothing}}(
                :clients => Array{WebsocketConnection, 1}(),
                :socket => nothing
            )
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
        self.server[:server] = Sockets.listen(host, port)
        Sockets.nagle(self.server[:server], config.useNagleAlgorithm)
        self.flags[:isopen] = true
        HTTP.listen(; server = self.server[:server],  options...) do io
            try
                headers = io.message
                validateUpgrade(headers)
                HTTP.setstatus(io, 101)
                key = string(HTTP.header(headers, "Sec-WebSocket-Key"))
                HTTP.setheader(io, "Sec-WebSocket-Accept" => acceptHash(key))
                HTTP.setheader(io, "Upgrade" => "websocket")
                HTTP.setheader(io, "Connection" => "Upgrade")

                startwrite(io)

                client = WebsocketConnection(io.stream, config, self.server[:clients])
                push!(self.server[:clients], client)
                callback(client)
                if HTTP.hasheader(headers, "Sec-WebSocket-Extensions")
                    close(client, CLOSE_REASON_EXTENSION_REQUIRED)
                else
                    startConnection(client, io)
                end
            catch err
                @error err exception = (err, catch_backtrace())
                HTTP.setstatus(io, 400)
                startwrite(io)
            end
        end
    catch err
        self.flags[:isopen] = false
        if typeof(err) === Base.IOError && err.msg === "accept: software caused connection abort (ECONNABORTED)"
            callback = self.callbacks[:closed]
            if callback isa Function
                callback((; host = host, port = port))
            else
                @info "The websocket server was closed cleanly:" host = host port = port
            end
            return
        end
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
    for client in self.server[:clients]
        send(client, data)
    end
end