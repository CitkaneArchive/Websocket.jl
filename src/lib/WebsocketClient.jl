struct WebsocketClient
    config::NamedTuple
    connect::Function
    callbacks::Dict{Symbol, Union{Bool, Function}}
    flags::Dict{Symbol, Bool}
    on::Function
       
    function WebsocketClient(config::NamedTuple = NamedTuple()) 
        @debug "WebsocketClient"                   
        self = new(
            makeConfig(config),
            (   url::String, 
                headers::Dict{String, String} = Dict{String, String}();
                    kwargs...
            ) -> makeConnection(self, url, headers; kwargs...),
            Dict{Symbol, Union{Bool, Function}}(
                :connect => false,
                :connectError => false,
            ),
            Dict{Symbol, Bool}(
                :isconnected => false
            ),
            (key::Symbol, cb::Function) -> on(self, key, cb)
        )
    end
    function on(
        self::WebsocketClient,
        key::Symbol,
        cb::Function
    )
        if haskey(self.callbacks, key)
            self.callbacks[key] = cb
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

    if self.flags[:isconnected]
        @error WebsocketError(
            """called "connect" on a WebsocketClient that is open or opening."""
        )
        return
    end
    self.flags[:isconnected] = true

    connection = WebsocketConnection(self)
    connected = Condition()

    @async try            
        wait(connected)
        if self.callbacks[:connect] isa Function            
            self.callbacks[:connect](connection)
        else
            throw(WebsocketError("""called connect() before registering ":connect" event."""))
        end
    catch err
        self.flags[:isconnected] = false
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
            connection,
            self,
            urlString,
            connected,
            headers;
                reuse_limit=0, 
                kwargs...
        )
    catch err
        self.flags[:isconnected] = false
        @async notify(connected, err; error = true)
    end
end
