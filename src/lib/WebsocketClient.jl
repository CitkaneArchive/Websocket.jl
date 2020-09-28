struct WebsocketClient
    config::NamedTuple
    callbacks::Dict{Symbol, Union{Bool, Function}}
    flags::Dict{Symbol, Bool}

    function WebsocketClient(; config...)
        @debug "WebsocketClient"
        config = merge(defaultConfig, (; config...), (; maskOutgoingPackets = true))
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

include("WebsocketConnection.jl")

function listen(
    self::WebsocketClient,
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

function makeConnection(
    self::WebsocketClient,
    urlString::String,
    headers::Dict{String, String};
        options...
)
    @debug "WebsocketClient.connect"
    options = merge((; options...), defaultOptions)
    if isopen(self)
        @error WebsocketError(
            """called "connect" on a WebsocketClient that is open or opening."""
        )
        return
    end
    connected = Condition()
    self.flags[:isopen] = true
    @async try
        connection = wait(connected)
        if self.callbacks[:connect] isa Function
            self.callbacks[:connect](connection)
            wait(connection.closed)
            self.flags[:isopen] = false
        else
            throw(error("""called connect() before registering ":connect" event."""))
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
