module Websocket

include("lib/WebsocketClient.jl")

client = WebsocketClient.connect("wss://echo.websocket.org")

client.send("hello")
client.send("hello new brave world")


for message in client.messages
    println(message)
end

end