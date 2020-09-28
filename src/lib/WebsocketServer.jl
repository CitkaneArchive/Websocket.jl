struct WebsocketServer
    config::NamedTuple
    callbacks::Dict{Symbol, Union{Bool, Function}}
    flags::Dict{Symbol, Bool}

    function WebsocketServer(; config...)
        @debug "WebsocketClient"
        config = merge(serverConfig, (; config...), (; maskOutgoingPackets = false, type = "server",))
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

function Base.listen(self::WebsocketServer, host::String = "localhost", port::Int = 8080; options...)
    @debug "WebsocketServer.listen"
    options = merge((; options...), serverOptions)
    HTTP.listen(host, port; options...) do http
        explain(http)
    end
end