module WebsocketClient

using HTTP, URIParser

include("utils.jl")
include("WebsocketConnection.jl")

export connect

struct Websocket
    url::String
    connection::WebsocketConnection
    send::Function
    messages::Channel
    
    function Websocket(
        url::String,
        io::HTTP.Streams.Stream,
        dataIn::Channel,
        dataOut::Channel
    )
        new(
            url,
            WebsocketConnection(io, dataIn, dataOut),
            (data) -> put!(dataOut, data),
            Channel(Inf)
        )
    end
end

function headers()
    Dict(
        "Upgrade" => "websocket",
        "Connection" => "Upgrade",
        "Sec-WebSocket-Key" => nonce(),
        "Sec-WebSocket-Version" => "13"
    )
end

function connect(url::String)
    sockets = Channel{Websocket}()
    @async_err HTTP.open("GET", url; headers = headers()) do stream
        startread(stream)
        #validhandshake(stream, headers)
        dataIn = Channel(Inf)
        dataOut = Channel(Inf)
        ws = Websocket(url, stream, dataIn, dataOut)
        put!(sockets, ws)
        while !eof(stream)
            data = readavailable(stream)
            put!(dataIn, data)
        end
    end
    ws = take!(sockets)
    close(sockets)
    ws
end

function validhandshake(stream, headers)
    return true
end

end
#=
using HTTP, URIParser
include("lib/utils.jl")

uri =  URI("wss://ws.bitstamp.net")
#@show uri.scheme
#@show uri.host
#@show Int(uri.port)
#@show uri.path
#@show uri.query
#@show uri.fragment
#@show uri.specifies_authority

options = (;
    hostname = "httpbin.org/ip",
    port = "80"
)
headers = Dict(
    "Upgrade" => "websocket",
    "Connection" => "Upgrade",
    "Sec-WebSocket-Key" => nonce(),
    "Sec-WebSocket-Version" => "13"
)

HTTP.open("GET", "wss://echo.websocket.org"; headers = headers) do http
    #startread(http)
    #@show http.message.status
    
    #explain(http)
    #explain(http.stream)
    #explain(http.message)
    #explain(http.message.request)
    ws = http.stream
end

end
=#