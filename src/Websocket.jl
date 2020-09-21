module Websocket
using HTTP, Base64
using MbedTLS: digest, MD_SHA1

include("opt/vars.jl")
include("opt/utils.jl")
include("lib/WebsocketClient.jl")

export WebsocketClient

end
