module Websocket
using HTTP, Base64, Sockets
using MbedTLS: digest, MD_SHA1

include("opt/vars.jl")
include("opt/utils.jl")
include("lib/WebsocketClient.jl")

export WebsocketClient, listen, send, logWSerror

function Base.open(client::WebsocketClient, url::String, headers::Dict{String, String} = Dict{String, String}();kwargs...)
    makeConnection(client, url, headers; kwargs...)
end
function Base.isopen(client::WebsocketClient)
    client.flags[:isopen]
end
function Base.close(ws::WebsocketConnection, reasonCode::Int = CLOSE_REASON_NORMAL)
    closeConnection(ws, reasonCode)
end
function logWSerror(err::WebsocketError)
    err.log()
end
function logWSerror(err::Exception)
    @error err
end


end

