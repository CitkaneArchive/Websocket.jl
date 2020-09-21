include("WebsocketFrame.jl")

struct WebsocketConnection
    io::Dict{Symbol, Any}
    maskBytes::IOBuffer
    frameHeader::IOBuffer
    closed::Condition
    close::Function
    send::Function
    on::Function

    function WebsocketConnection(client::WebsocketClient)
        @debug "WebsocketConnection"
        maskBytes = newBuffer(4)
        frameHeader = newBuffer(10)
        atexit(function() 
            #closeConnection(self, CLOSE_REASON_GOING_AWAY)
            #wait(self.closed)
            #!eof(self.io[:stream]) && close(self.io[:stream])
            #exit()
        end)

        self = new(
            Dict{Symbol, Any}(                                          #io
                :stream => nothing,
                :callbacks => Dict{Symbol, Union{Bool, Function}}(
                    :message => false,
                    :error => false,
                    :close => false
                ),
                #=
                :channels => Dict{Symbol, Channel}(
                    :message => Channel(),
                    :error => Channel{Exception}()
                ),
                =#
                :currentFrame => WebsocketFrame(maskBytes, frameHeader),
            ),
            maskBytes,                                                  #maskBytes
            frameHeader,                                                #frameHeader
            Condition(),                                                #closed
            (   reasonCode::Int = CLOSE_REASON_NORMAL                   #close
            ) -> closeConnection(self, reasonCode),
            data::String -> send(self, data::String),                   #send
            (key::Symbol, cb::Function) -> on(self, key, cb)    #on
        )
        closed = @async begin
            reason = wait(self.closed)        
            callback = self.io[:callbacks][:close]
            callback isa Function && callback(reason)  
        end

        self
    end
    function on(
        self::WebsocketConnection,
        key::Symbol,
        cb::Function
    )
        if haskey(self.io[:callbacks], key)
            if !(self.io[:callbacks][key] isa Function)
                self.io[:callbacks][key] = cb
                #=
                if key === :close
                    reason = wait(self.closed)
                    client.flags[:isconnected] = false
                    cb(reason)
                else
                    for payload in self.io[:channels][key]
                        cb(payload)
                    end
                end
                =#
            end
        end
    end
    #=
    function on(self::WebsocketConnection, client::WebsocketClient, key::Symbol, cb::Function)
        flags = self.io[:flags]
        channels = self.io[:channels]
        if !haskey(flags, key)
            @warn """The "$key" event is not recognised"""
            return
        end
        if flags[key]
            @warn """The event "$key" has already been set"""
            return
        end
        flags[key] = true
        self.io[:events] = @async begin
            if key === :close
                reason = wait(self.closed)
                client.flags[:isconnected] = false
                cb(reason)
            elseif key === :error
                while isopen(channels[key]) 
                    for err in channels[key]
                        cb(err)
                    end
                end
            else
                while isopen(channels[key]) 
                        for payload in channels[key]
                        try
                            cb(payload)
                        catch err
                            if flags[:error]
                                put!(channels[:error], err)
                            else
                                @error "error in callback to websocket." exception = (err, catch_backtrace())
                            end
                        end
                    end
                end
            end
        end
    end
    =#
end

function validateHandshake(headers::Dict{String, String}, request::HTTP.Messages.Response)
    if request.status != 101
        throw(WebsocketError("connection error with status: $(request.status)"))
    end
    if !HTTP.hasheader(request, "Connection", "Upgrade")
        throw(WebsocketError("""did not receive "Connection: Upgrade" """))
    end
    if !HTTP.hasheader(request, "Upgrade", "websocket")
        throw(WebsocketError("""did not receive "Upgrade: websocket" """))
    end
    if !HTTP.hasheader(request, "Sec-WebSocket-Accept", acceptHash(headers["Sec-WebSocket-Key"]))
        throw(WebsocketError("""invalid "Sec-WebSocket-Accept" response from server"""))
    end
end

function connect(
    self::WebsocketConnection,
    client::WebsocketClient,
    url::String,
    connected::Condition,
    headers::Dict{String, String};
        kwargs...
)
    @debug "WebsocketConnection.connect"
    HTTP.open("GET", url, headers;
        kwargs...
    ) do io
        try
            request = startread(io)
            validateHandshake(headers, request)
            self.io[:stream] = io.stream
            notify(connected)
        catch err
            notify(connected, err; error = true)
            return
        end
        #channels = self.io[:channels]
        while !eof(io)
            data = readavailable(io)
            handleSocketData(self, data)
        end
        client.flags[:isconnected] = false 
    end
end
function closeConnection(self::WebsocketConnection, reasonCode::Int)
    if !haskey(CLOSE_DESCRIPTIONS, reasonCode)
        throw(WebsocketError("invalid close reason code: $(reasonCode)."))
    end
    sendCloseFrame(self, reasonCode)
    #close(self.io[:stream])
end
# Send data
function send(self::WebsocketConnection, data::String)
    @debug "WebsocketConnection.send"
    frame = WebsocketFrame(self.maskBytes, self.frameHeader, textbuffer(data))
    frame.inf[:opcode] = TEXT_FRAME
    fragmentAndSend(self, frame)
end

function fragmentAndSend(self::WebsocketConnection, frame::WebsocketFrame)
    @debug "WebsocketConnection.fragmentAndSend"
    frame.inf[:fin] = true
    sendFrame(self, frame)
end

function sendFrame(self::WebsocketConnection, frame::WebsocketFrame)
    @debug "WebsocketConnection.sendFrame"
    frame.inf[:mask] = true
    data = toBuffer(frame)
    isopen(self.io[:stream]) && write(self.io[:stream], read(data))
    close(data)
end

function sendCloseFrame(self::WebsocketConnection, reasonCode::Int)
    description = CLOSE_DESCRIPTIONS[reasonCode]
    frame = WebsocketFrame(self.maskBytes, self.frameHeader, textbuffer(description));
    frame.inf[:opcode] = CONNECTION_CLOSE_FRAME
    frame.inf[:fin] = true
    frame.inf[:closeStatus] = reasonCode
    sendFrame(self, frame)
end
# End send data

# Receive data
function handleSocketData(self::WebsocketConnection, data::Array{UInt8,1})
    processReceivedData(self, data)
end

function processReceivedData(self::WebsocketConnection, data::Array{UInt8,1})
    frame = self.io[:currentFrame]
    !frame.addData(data) && return
    processFrame(self, frame)
    self.io[:currentFrame] = WebsocketFrame(self.maskBytes, self.frameHeader)
end

function processFrame(self::WebsocketConnection, frame::WebsocketFrame)
    inf = (; frame.inf...)
    opcode = inf.opcode

    if opcode === BINARY_FRAME

    elseif opcode === TEXT_FRAME
        data = inf.binaryPayload
        callback = self.io[:callbacks][:message]
        callback isa Function && callback(String(data))
    elseif opcode === CONTINUATION_FRAME

    elseif opcode === PING_FRAME

    elseif opcode === PONG_FRAME

    elseif opcode === CONNECTION_CLOSE_FRAME
        data = inf.binaryPayload
        reason = (;
            code = inf.closeStatus,
            description = String(data),
        )
        !eof(self.io[:stream]) && close(self.io[:stream])
        sleep(1)
        notify(self.closed, reason; all = true)
        @info "notified"
    else

    end
end
# End receive data


