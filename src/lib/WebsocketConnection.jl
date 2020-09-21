include("WebsocketFrame.jl")
const ioTypes = Union{Nothing, WebsocketFrame, HTTP.ConnectionPool.Transaction, Timer}

struct WebsocketConnection
    config::NamedTuple
    io::Dict{Symbol, ioTypes}
    callbacks::Dict{Symbol, Union{Bool, Function}}
    maskBytes::IOBuffer
    frameHeader::IOBuffer
    closed::Condition
    close::Function
    send::Function
    on::Function
    ping::Function

    function WebsocketConnection(config::NamedTuple)
        @debug "WebsocketConnection"
        maskBytes = newBuffer(4)
        frameHeader = newBuffer(10)
        atexit(() -> (
            if isopen(self.io[:stream])               
                close(self.io[:stream])
                wait(self.closed)
                sleep(0.001)             
            end
        ))
        @async begin
            reason = wait(self.closed)
            callback = self.callbacks[:close]
            if callback isa Function
                @async callback(reason)
            else
                @warn "websocket connection closed." reason...
            end
        end
        
        self = new(
            config,                                                     #config
            Dict{Symbol, ioTypes}(                                      #io
                :stream => nothing,
                :currentFrame => WebsocketFrame(config, maskBytes, frameHeader),
                :closeTimeout => nothing,
            ),
            Dict{Symbol, Union{Bool, Function}}(                        #callbacks
                :message => false,
                :error => false,
                :close => false,
                :pong => false
            ),
            maskBytes,                                                  #maskBytes
            frameHeader,                                                #frameHeader
            Condition(),                                                #closed
            (   reasonCode::Int = CLOSE_REASON_NORMAL                   #close
            ) -> closeConnection(self, reasonCode),
            data::String -> send(self, data::String),                   #send
            (key::Symbol, cb::Function) -> on(self, key, cb),           #on
            data::Union{String, Number} -> ping(self, data)             #ping
        )
    end
    function on(
        self::WebsocketConnection,
        key::Symbol,
        cb::Function
    )
        if haskey(self.callbacks, key)
            if !(self.callbacks[key] isa Function)
                self.callbacks[key] = data -> (
                    try 
                        cb(data)
                    catch err
                        @error "error in WebsocketConnection callback." exception = (err, catch_backtrace())
                    end
                )
            end
        end
    end
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
    config::NamedTuple,
    url::String,
    connected::Condition,
    headers::Dict{String, String};
        options...
)
    @debug "WebsocketConnection.connect"
    let self
        HTTP.open("GET", url, headers;
            options...
        ) do io
            Sockets.nagle(io.stream.c.io.bio, config.useNagleAlgorithm)
            try
                request = startread(io)
                validateHandshake(headers, request)
                self = WebsocketConnection(config)
                self.io[:stream] = io.stream
                notify(connected, self)
            catch err
                notify(connected, err; error = true)
                return
            end
            while !eof(io)
                data = readavailable(io)
                handleSocketData(self, data)
            end
            closeConnection(self, CLOSE_REASON_ABNORMAL)
            wait(self.closed)
        end
    end
end
function closeConnection(self::WebsocketConnection, reasonCode::Int)
    if !haskey(CLOSE_DESCRIPTIONS, reasonCode)
        @error WebsocketError("invalid close reason code: $(reasonCode).")
        reasonCode = CLOSE_REASON_NOT_PROVIDED
    end
    nowire = [
        CLOSE_REASON_NOT_PROVIDED,
        CLOSE_REASON_ABNORMAL
    ]
    if !(reasonCode in nowire) && isopen(self.io[:stream])        
        sendCloseFrame(self, reasonCode)
        self.io[:closeTimeout] = Timer(timer -> (
            try
                isopen(self.io[:stream]) && close(self.io[:stream])
            catch
            end
        ), self.config.closeTimeout)
    else
        reason = (;
            code = reasonCode,
            description = CLOSE_DESCRIPTIONS[reasonCode],
        )        
        isopen(self.io[:stream]) && close(self.io[:stream])
        @async notify(self.closed, reason; all = true)       
    end
end

# Send data
function send(self::WebsocketConnection, data::String)
    @debug "WebsocketConnection.send"
    frame = WebsocketFrame(self.config, self.maskBytes, self.frameHeader, textbuffer(data))
    frame.inf[:opcode] = TEXT_FRAME
    fragmentAndSend(self, frame)
end

function sendCloseFrame(self::WebsocketConnection, reasonCode::Int)
    description = CLOSE_DESCRIPTIONS[reasonCode]
    frame = WebsocketFrame(self.config, self.maskBytes, self.frameHeader, textbuffer(description));
    frame.inf[:opcode] = CONNECTION_CLOSE_FRAME
    frame.inf[:fin] = true
    frame.inf[:closeStatus] = reasonCode
    sendFrame(self, frame)
end
function ping(self::WebsocketConnection, data::Union{String, Number})
    data = textbuffer(data)
    size(data, 1) > 125 && (data = data[1:125, 1])
    frame = WebsocketFrame(self.config, self.maskBytes, self.frameHeader, data)
    frame.inf[:fin] = true
    frame.inf[:opcode] = PING_FRAME
    sendFrame(self, frame)
end
pong(self::WebsocketConnection, data::Union{String, Number}) = pong(self, textbuffer(data))
function pong(self::WebsocketConnection, data::Array{UInt8,1})
    size(data, 1) > 125 && (data = data[1:125, 1])
    frame = WebsocketFrame(self.config, self.maskBytes, self.frameHeader, data)
    frame.inf[:fin] = true
    frame.inf[:opcode] = PONG_FRAME
    sendFrame(self, frame)
end
function fragmentAndSend(self::WebsocketConnection, frame::WebsocketFrame)
    @debug "WebsocketConnection.fragmentAndSend"
    frame.inf[:fin] = true
    sendFrame(self, frame)
end

function sendFrame(self::WebsocketConnection, frame::WebsocketFrame)
    @debug "WebsocketConnection.sendFrame"
    frame.inf[:mask] = self.config.maskOutgoingPackets
    data = toBuffer(frame)
    isopen(self.io[:stream]) && write(self.io[:stream], read(data))
    close(data)
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
    self.io[:currentFrame] = WebsocketFrame(self.config, self.maskBytes, self.frameHeader)
end

function processFrame(self::WebsocketConnection, frame::WebsocketFrame)
    
    inf = (; frame.inf...)
    opcode = inf.opcode

    if opcode === BINARY_FRAME

    elseif opcode === TEXT_FRAME
        data = inf.binaryPayload
        callback = self.callbacks[:message]
        callback isa Function && callback(String(data))
    elseif opcode === CONTINUATION_FRAME

    elseif opcode === PING_FRAME
        @info "received ping"
        pong(self, frame.inf[:binaryPayload])
    elseif opcode === PONG_FRAME
        callback = self.callbacks[:pong]
        if callback isa Function
            callback(String(frame.inf[:binaryPayload]))
        end
    elseif opcode === CONNECTION_CLOSE_FRAME
        data = inf.binaryPayload
        reason = (;
            code = inf.closeStatus,
            description = String(data),
        )
        if self.io[:closeTimeout] isa Timer && isopen(self.io[:closeTimeout])
            close(self.io[:closeTimeout])
        end
        notify(self.closed, reason; all = true)
        isopen(self.io[:stream]) && close(self.io[:stream])
    else

    end
end
# End receive data


