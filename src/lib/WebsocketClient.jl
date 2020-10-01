struct WebsocketClient
    config::NamedTuple
    callbacks::Dict{Symbol, Union{Bool, Function}}
    flags::Dict{Symbol, Bool}

    function WebsocketClient(; config...)
        @debug "WebsocketClient"
        config = merge(clientConfig, (; config...), (; maskOutgoingPackets = true, type = "client"))
        self = new(
            config,
            Dict{Symbol, Union{Bool, Function}}(
                :connect => false,
                :connectError => false,
            ),
            Dict{Symbol, Bool}(
                :isopen => false
            )
        )
    end
end

function listen(
    self::WebsocketClient,
    key::Symbol,
    cb::Function
)
    if !haskey(self.callbacks, key)
        return @warn "WebsocketClient has no listener for :$key."
    end
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

function makeConnection(
    self::WebsocketClient,
    urlString::String,
    headers::Dict{String, String};
        options...
)
    @debug "WebsocketClient.connect"
    if isopen(self)
        @warn """called "connect" on a WebsocketClient that is open or opening."""
        return
    end
    options = merge((; options...), clientOptions)
    connected = Condition()
    self.flags[:isopen] = true
    @async try
        connection = wait(connected)
        if self.callbacks[:connect] isa Function
            self.callbacks[:connect](connection)
            wait(connection.closed)
            self.flags[:isopen] = false
        else
            throw(error("""called "open" before registering ":connect" event."""))
        end
    catch err
        err = ConnectError(err, catch_backtrace())
        self.flags[:isopen] = false
        if self.callbacks[:connectError] isa Function
            self.callbacks[:connectError](err)
        else
            err.log()
            exit()
        end
    end

    try
        headers = makeHeaders(headers)
        if !(headers["Sec-WebSocket-Version"] in ["8", "13"])
            throw(error("only version 8 and 13 of websocket protocol supported."))
        end
        if haskey(headers, "Sec-WebSocket-Extensions")
            throw(error("websocket extensions not supported in client"))
        end
        connect(
            self.config,
            urlString,
            connected,
            headers;
                options...
        )
    catch err
        @async notify(connected, err; error = true)
    end
end

function validateHandshake(headers::Dict{String, String}, request::HTTP.Messages.Response)

    if request.status != 101
        throw(error("connection error with status: $(request.status)"))
    end
    if !HTTP.hasheader(request, "Connection", "Upgrade")
        throw(error("""did not receive "Connection: Upgrade" """))
    end
    if !HTTP.hasheader(request, "Upgrade", "websocket")
        throw(error("""did not receive "Upgrade: websocket" """))
    end
    if !HTTP.hasheader(request, "Sec-WebSocket-Accept", acceptHash(headers["Sec-WebSocket-Key"]))
        throw(error("""invalid "Sec-WebSocket-Accept" response from server"""))
    end
    if HTTP.hasheader(request, "Sec-WebSocket-Extensions")
        @warn "Server uses websocket extensions" (;
            value = HTTP.header(request, "Sec-WebSocket-Extensions"),
            caution = "Websocket extensions are not supported in the client and may cause connection closure."
        )...
    end
end

function connect(
    config::NamedTuple,
    url::String,
    connected::Condition,
    headers::Dict{String, String};
        options...
)
    @debug "WebsocketClient.connect"
    let self
        HTTP.open("GET", url, headers;
            options...
        ) do io
            tcp = io.stream.c.io isa TCPSocket ? io.stream.c.io : io.stream.c.io.bio
            Sockets.nagle(tcp, config.useNagleAlgorithm)
            try
                request = startread(io)
                validateHandshake(headers, request)
                self = WebsocketConnection(io.stream, config)
                notify(connected, self)
            catch err
                notify(connected, err; error = true)
                return
            end
            startConnection(self, io)
        end
    end
end
