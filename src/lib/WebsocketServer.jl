"""
    WebsocketServer([; options...])

Constructs a new WebsocketServer, overriding [`serverConfig`](@ref) with the passed options.

# Example
```julia
using Websocket
server = WebsocketServer([; options...])
```
"""
struct WebsocketServer
    config::NamedTuple
    callbacks::Dict{Symbol, Union{Bool, Function}}
    flags::Dict{Symbol, Bool}
    server::Dict{Symbol, Union{Sockets.TCPServer, Array{WebsocketConnection, 1}, Nothing}}

    function WebsocketServer(; config...)
        @debug "WebsocketClient"
        config = merge(serverConfig, (; config...))
        config = merge(config, (; maskOutgoingPackets = false, type = "server",))
        self = new(
            config,
            Dict{Symbol, Union{Bool, Function}}(
                :client => false,
                :connectError => false,
                :closed => false,
                :listening => false
            ),
            Dict{Symbol, Bool}(
                :isopen => false
            ),
            Dict{Symbol, Union{Sockets.TCPServer, Array{WebsocketConnection, 1}, Nothing}}(
                :clients => Array{WebsocketConnection, 1}(),
                :socket => nothing
            )
        )
    end

end
"""
    listen(server::Websocket.WebsocketServer, event::Symbol, callback::Function)
Register event callbacks onto a server. The callback must be a function with exactly one argument.

Valid events are:
- :listening
- :client
- :connectError
- :closed

!!! note ":listening"
    Triggered when the server TCP socket opens
    ```julia
    listen(server, :listening, details::NamedTuple -> (
        # details.port::Int
        # details.host::Union{Sockets.IPv4, Sockets.IPv6}
    ))
    ```
!!! note ":client"
    Triggered when a client connects to the server

    Returns a [`WebsocketConnection`](@ref Websocket-Connection) to the callback.

    ```julia
    listen(server, :client, client::WebsocketConnection -> (
        begin
            # ...
        end
    ))
    ```
!!! note ":connectError"
    Triggered when an attempt to open a TCP socket listener fails
    ```julia
    listen(server, :connectError, err::WebsocketError.ConnectError -> (
        # err.msg::String
        # err.log::Function -> logs the error message with stack trace
    ))
    ```
!!! note ":closed"
    Triggered when the server TCP socket closes
    ```julia
    listen(server, :closed, details::NamedTuple -> (
        # details.port::Int
        # details.host::Union{Sockets.IPv4, Sockets.IPv6}
    ))
    ```
"""
function listen(
    self::WebsocketServer,
    event::Symbol,
    cb::Function
)
    if !haskey(self.callbacks, event)
        return @warn "WebsocketServer has no listener for :$event."
    end
    if haskey(self.callbacks, event) && !(self.callbacks[event] isa Function)
        self.callbacks[event] = data -> (
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

function validateUpgrade(headers::HTTP.Messages.Request)
    if !HTTP.hasheader(headers, "Upgrade", "websocket")
        throw(error("""did not receive "Upgrade: websocket" """))
    end
    if !HTTP.hasheader(headers, "Connection", "Upgrade") || HTTP.hasheader(headers, "Connection", "keep-alive upgrade")
        throw(error("""did not receive "Connection: Upgrade" """))
    end
    if !HTTP.hasheader(headers, "Sec-WebSocket-Version", "13") && !HTTP.hasheader(headers, "Sec-WebSocket-Version", "8")
        throw(error("""did not receive "Sec-WebSocket-Version: [13 or 8]" """))
    end
    if !HTTP.hasheader(headers, "Sec-WebSocket-Key")
        throw(error("""did not receive "Sec-WebSocket-Key" header."""))
    end
end

"""
    serve(server::Websocket.WebsocketServer, [port::Int, host::String; options...])
Opens up a TCP connection listener. Blocks while the server is listening.

Defaults:
- port: 8080
- host: "localhost"

`; options...` are passed to the underlying [HTTP.servers.listen](https://juliaweb.github.io/HTTP.jl/stable/public_interface/#Server-/-Handlers-1)

# Example
```julia
closed = Condition()
#...
@async serve(server, 8081, "localhost")
#...
wait(closed)
```
"""
function serve(self::WebsocketServer, port::Int = 8080, host::String = "localhost"; options...)
    @debug "WebsocketServer.listen"
    config = self.config
    options = merge(serverOptions, (; options...))

    try
        host = getaddrinfo(host)
        if config.ssl
            tlsconfig = HTTP.Servers.SSLConfig(config.sslcert, config.sslkey)
            options = merge(options, (; sslconfig = tlsconfig))
        end
        callback = self.callbacks[:client]
        callback === false && throw(error("tried to bind the server before registering \":client\" handler"))
        self.server[:server] = Sockets.listen(host, port)
        
        VERSION >= v"1.3" && Sockets.nagle(self.server[:server], config.useNagleAlgorithm) #Sockets.nagle needs Julia >= 1.3

        self.flags[:isopen] = true
        if self.callbacks[:listening] isa Function
            self.callbacks[:listening]((; port = port, host = host))
        end
        HTTP.listen(; server = self.server[:server],  options...) do io
            try
                headers = io.message
                validateUpgrade(headers)
                HTTP.setstatus(io, 101)
                key = string(HTTP.header(headers, "Sec-WebSocket-Key"))
                HTTP.setheader(io, "Sec-WebSocket-Accept" => acceptHash(key))
                HTTP.setheader(io, "Upgrade" => "websocket")
                HTTP.setheader(io, "Connection" => "Upgrade")

                startwrite(io)

                client = WebsocketConnection(io.stream, config, self.server[:clients])
                push!(self.server[:clients], client)
                callback(client)
                if HTTP.hasheader(headers, "Sec-WebSocket-Extensions")
                    close(client, CLOSE_REASON_EXTENSION_REQUIRED)
                else
                    startConnection(client, io)
                end
            catch err
                @error err exception = (err, catch_backtrace())
                HTTP.setstatus(io, 400)
                startwrite(io)
            end
        end
    catch err
        self.flags[:isopen] = false
        if typeof(err) === Base.IOError && occursin("software caused connection abort", err.msg)
            callback = self.callbacks[:closed]
            if callback isa Function
                callback((; host = host, port = port))
            else
                @info "The websocket server was closed cleanly:" host = host port = port
            end
            return
        end
        err = ConnectError(err, catch_backtrace())
        callback = self.callbacks[:connectError]
        if callback isa Function
            callback(err)
        else
            err.log()
        end
    end
end

"""
    emit(server::Websocket.WebsocketServer, data::Union{Array{UInt8,1}, String, Number})
Sends the given `data` as a message to all clients connected to the server.

# Example
```julia
emit(server, "Hello everybody from your loving server.")
```
"""
function emit(self::WebsocketServer, data::Union{Array{UInt8,1}, String, Number})
    for client in self.server[:clients]
        send(client, data)
    end
end
"""
    close(server::Websocket.WebsocketServer)
Gracefully disconnects all connected clients, then closes the TCP socket listener.
"""
function Base.close(self::WebsocketServer)    
    @sync begin
        for client in self.server[:clients]
            close(client, CLOSE_REASON_GOING_AWAY)
            @async wait(client.closed)
        end
    end
    close(self.server[:server])
end
"""
    isopen(server::Websocket.WebsocketServer)::Bool
Returns a Bool indication if the server TCP listener is open.
"""
function Base.isopen(server::WebsocketServer)
    server.flags[:isopen]
end
"""
    length(server::WebsocketServer)::Int
Returns the number of clients connected to the server. 
"""
function Base.length(self::WebsocketServer)
    length(self.server[:clients])
end
