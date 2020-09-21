struct WebsocketClient
    config::NamedTuple
    open::Function
    callbacks::Dict{Symbol, Union{Bool, Function}}
    flags::Dict{Symbol, Bool}
    on::Function

    function WebsocketClient(; config...)
        @debug "WebsocketClient"
        config = merge(defaultConfig, (; config...), (; maskOutgoingPackets = true))
        self = new(
            config,
            (   url::String,
                headers::Dict{String, String} = Dict{String, String}();
                    kwargs...
            ) -> makeConnection(self, url, headers; kwargs...),
            Dict{Symbol, Union{Bool, Function}}(
                :connect => false,
                :connectError => false,
            ),
            Dict{Symbol, Bool}(
                :isopen => false
            ),
            (key::Symbol, cb::Function) -> on(self, key, cb)
        )
    end
    function on(
        self::WebsocketClient,
        key::Symbol,
        cb::Function
    )
        if haskey(self.callbacks, key) && !(self.callbacks[key] isa Function)
            self.callbacks[key] = data -> (
                try
                    cb(data)
                catch err
                    @error "error in WebsocketClient callback." exception = (err, catch_backtrace())
                end
            )
        end
    end
end

include("WebsocketConnection.jl")

function makeConnection(
    self::WebsocketClient,
    urlString::String,
    headers::Dict{String, String};
        kwargs...
)
    @debug "WebsocketClient.connect"
    options = merge((; kwargs...), defaultOptions)
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
            throw(WebsocketError("""called connect() before registering ":connect" event."""))
        end
    catch err
        self.flags[:isopen] = false
        if self.callbacks[:connectError] isa Function
            self.callbacks[:connectError](err)
        else
            println()
            @error "error in websocket connection" exception = (err, catch_backtrace())
            println()
            exit()
        end
    end

    try
        headers = makeHeaders(headers)
        if !(headers["Sec-WebSocket-Version"] in ["8", "13"])
            throw(WebsocketError("only version 8 and 13 of websocket protocol supported."))
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
