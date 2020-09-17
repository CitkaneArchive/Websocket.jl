include("WebsocketConnection.jl")

mutable struct WebsocketClient
    url::String
    connection::Union{Nothing, WebsocketConnection}
    send::Function
    eventFlags::Dict{Symbol, Bool}
    events::Dict{Symbol, Channel}
    on::Function
    connect::Function

    function WebsocketClient(
        url::String;
            config::NamedTuple = NamedTuple(),
    )
        dataOut = Channel(Inf)
        self = new(
            url,
            nothing,
            (data) -> put!(dataOut, data),
            Dict{Symbol, Bool}(
                :message => false,
                :connect => false,
                :error => false,
            ),
            Dict{Symbol, Channel}(
                :message => Channel(),
                :connect => Channel(),
                :error => Channel(),
            )
        )
        self.connect = (;
            headers::NamedTuple = NamedTuple(),
            options::NamedTuple = NamedTuple(),
        ) -> connect(self, dataOut; headers, options)
        self.on = (event::String, cb::Function) -> on(self, event, cb)
        self
    end
end

function on(self::WebsocketClient, event::String, cb::Function)
    key = Symbol(event)
    if !haskey(self.eventFlags, key)
        @warn """The event "$event" is not a recognised event"""
        return
    end
    if self.eventFlags[key]
        @warn """The event "$event" has already been set"""
        return
    end
    self.eventFlags[key] = true
    @async begin
        for payload in self.events[key]
            cb(payload)
        end
    end
end

function connect(client::WebsocketClient, dataOut::Channel)
    ready = Condition()
    @async try
        HTTP.open("GET", client.url; headers = makeHeaders()) do stream
            startread(stream)
            #validhandshake(stream, headers)
            dataIn = Channel(Inf)
            client.connection = WebsocketConnection(stream, dataIn, dataOut)
            eventFlags = client.eventFlags
            #notify(ready, "error"; error = true)
            notify(ready)
            while !eof(stream)
                data = readavailable(stream)
                eventFlags[:message] && put!(client.events[:message], data)
                #put!(dataIn, data)
            end
            eventFlags[:disconnect] && put(client.events[:disconnect], client.url)
        end
    catch err
        @error errorMsg exception = (err, catch_backtrace())
        exit()
    end
    wait(ready)
    client
end

function validhandshake(stream, headers)
    return true
end