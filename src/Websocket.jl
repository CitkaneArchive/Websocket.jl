module Websocket
using HTTP, Base64, Sockets, MbedTLS

export WebsocketServer, WebsocketClient, WebsocketConnection, listen, serve, send, emit, logWSerror, ping

include("opt/vars.jl")
include("opt/utils.jl")
include("lib/WebsocketConnection.jl")
include("lib/WebsocketClient.jl")
include("lib/WebsocketServer.jl")

function Base.open(client::WebsocketClient, url::String, headers::Dict{String, String} = Dict{String, String}();kwargs...)
    makeConnection(client, url, headers; kwargs...)
end
function Base.isopen(client::WebsocketClient)
    client.flags[:isopen]
end
function Base.close(ws::WebsocketConnection, reasonCode::Int = CLOSE_REASON_NORMAL, description::String = "")
    closeConnection(ws, reasonCode, description)
end
function Base.broadcast(self::WebsocketConnection, data::Union{Array{UInt8,1}, String, Number})
    self.sockets === nothing && return
    for connection in self.sockets
        connection.id !== self.id && send(connection, data)
    end
end
function logWSerror(err::WebsocketError)
    err.log()
end
function logWSerror(err::Exception)
    @error err
end


end

