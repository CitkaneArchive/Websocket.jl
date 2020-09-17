module Websocket
using HTTP

include("opt/utils.jl")
include("lib/WebsocketClient.jl")

function connect(url::String)
    client = WebsocketClient(url)
    client.connect()
end

end
