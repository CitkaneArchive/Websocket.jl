include("WebsocketFrame.jl")
const ioTypes = Union{Nothing, WebsocketFrame, HTTP.ConnectionPool.Transaction, Timer, Closereason}

struct WebsocketConnection
    config::NamedTuple
    io::Dict{Symbol, ioTypes}
    callbacks::Dict{Symbol, Union{Bool, Function}}
    buffers::NamedTuple
    closed::Condition

    function WebsocketConnection(config::NamedTuple)
        @debug "WebsocketConnection"
        buffers = (
            maskBytes = IOBuffer(; maxsize = 4),
            frameHeader = IOBuffer(; maxsize = 10),
            outBuffer = config.fragmentOutgoingMessages ? IOBuffer(; maxsize = Int(config.fragmentationThreshold)+10) : IOBuffer(),
            inBuffer = IOBuffer(; maxsize = Int(config.maxReceivedFrameSize)),
            fragmentBuffer = IOBuffer(; maxsize = Int(config.maxReceivedMessageSize))
        )
        atexit(() -> (
            if isopen(self.io[:stream])
                closeConnection(self, CLOSE_REASON_ABNORMAL, "julia process exited.")
                wait(self.closed)
                sleep(0.001)
            end
        ))
        @async begin
            reason = wait(self.closed)
            for buffer in collect(self.buffers)
                close(buffer)
            end
            callback = self.callbacks[:close]
            if callback isa Function
                callback(reason)
            else
                @warn "websocket connection closed." reason...
            end
        end

        self = new(
            config,                                                     #config
            Dict{Symbol, ioTypes}(                                      #io
                :stream => nothing,
                :currentFrame => WebsocketFrame(config, buffers),
                :closeTimeout => nothing,
                :closeReason => nothing,
            ),
            Dict{Symbol, Union{Bool, Function}}(                        #callbacks
                :message => false,
                :error => false,
                :close => false,
                :pong => false
            ),
            buffers,                                                    #buffers
            Condition(),                                                #closed
        )
    end
end

function listen(
    self::WebsocketConnection,
    key::Symbol,
    cb::Function
)
    if haskey(self.callbacks, key)
        if !(self.callbacks[key] isa Function)
            self.callbacks[key] = data -> (
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
end

function validateHandshake(headers::Dict{String, String}, request::HTTP.Messages.Response)
    if request.status != 101
        throw(error("connection error with status: $(request.status)"))
    end
    if !HTTP.hasheader(request, "Connection", "Upgrade")
        throw(error("""did not receive "Connection: Upgrade" """))
    end
    if !HTTP.hasheader(request, "Upgrade", "websocket")
        throw(error("""did not receive "Upgrade: websocket" """))
    end
    if !HTTP.hasheader(request, "Sec-WebSocket-Accept", acceptHash(headers["Sec-WebSocket-Key"]))
        throw(error("""invalid "Sec-WebSocket-Accept" response from server"""))
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
            if io.stream.c.io isa TCPSocket
                Sockets.nagle(io.stream.c.io, config.useNagleAlgorithm)
            else
                Sockets.nagle(io.stream.c.io.bio, config.useNagleAlgorithm)
            end
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
                try
                    seekend(self.buffers.inBuffer)
                    unsafe_write(self.buffers.inBuffer, pointer(data), length(data))
                    processReceivedData(self)
                    
                catch err
                    err = FrameError(err, catch_backtrace())
                    if self.callbacks[:error] isa Function
                        self.callbacks[:error](err)
                    else
                        err.log()   
                    end
                    closeConnection(self, CLOSE_REASON_INVALID_DATA, err.msg)
                    close(self.io[:stream])
                    break
                end
            end
            
            @async begin
                (   self.io[:closeTimeout] !== nothing &&
                    isopen(self.io[:closeTimeout]) 
                ) && sleep(0.001)
                
                if self.io[:closeReason] === nothing
                    self.io[:closeReason] = Closereason(CLOSE_REASON_ABNORMAL)
                end
                notify(self.closed, self.io[:closeReason]; all = true)
            end
        end
    end
end
function closeConnection(self::WebsocketConnection, reasonCode::Int, reason::String)
    closereason = Closereason(reasonCode, reason)
    !closereason.valid && throw(error("invalid connection close code."))

    self.io[:closeReason] = closereason
    if isopen(self.io[:stream])
        sendCloseFrame(self, reasonCode)
        self.io[:closeTimeout] = Timer(timer -> (
            try
                isopen(self.io[:stream]) && close(self.io[:stream])
            catch
            end
        ), self.config.closeTimeout)
    else
        isopen(self.io[:stream]) && close(self.io[:stream])
    end
end

# Send data
send(self::WebsocketConnection, data::Number) = send(self, string(data))
send(self::WebsocketConnection, data::String) = send(self, textbuffer(data))
function send(self::WebsocketConnection, data::Array{UInt8,1})
    @debug "WebsocketConnection.send"
    try
        frame = WebsocketFrame(self.config, self.buffers, data)
        frame.inf[:opcode] = self.config.binary ? BINARY_FRAME : TEXT_FRAME
        fragmentAndSend(self, frame)
    catch err
        err = FrameError(err, catch_backtrace())
        if self.callbacks[:error] isa Function
            self.callbacks[:error](err)
        else
            err.log()
        end
    end
end

function sendCloseFrame(self::WebsocketConnection, reasonCode::Int)
    description = CLOSE_DESCRIPTIONS[reasonCode]
    frame = WebsocketFrame(self.config, self.buffers, textbuffer(description));
    frame.inf[:opcode] = CONNECTION_CLOSE_FRAME
    frame.inf[:fin] = true
    frame.inf[:closeStatus] = reasonCode
    sendFrame(self, frame)
end
ping(self::WebsocketConnection, data::Number) = ping(self, String(data))
function ping(self::WebsocketConnection, data::String)
    try
        data = textbuffer(data)
        size(data, 1) > 125 && (data = data[1:125, 1])
        frame = WebsocketFrame(self.config, self.buffers, data)
        frame.inf[:fin] = true
        frame.inf[:opcode] = PING_FRAME
        sendFrame(self, frame)
    catch err
        err = FrameError(err, catch_backtrace())
        if self.callbacks[:error] isa Function
            self.callbacks[:error](err)
        else
            err.log()
        end
    end
end
pong(self::WebsocketConnection, data::Union{String, Number}) = pong(self, textbuffer(data))
function pong(self::WebsocketConnection, data::Array{UInt8,1})
    size(data, 1) > 125 && (data = data[1:125, 1])
    frame = WebsocketFrame(self.config, self.buffers, data)
    frame.inf[:fin] = true
    frame.inf[:opcode] = PONG_FRAME
    sendFrame(self, frame)
end
function fragmentAndSend(
    self::WebsocketConnection,
    frame::WebsocketFrame,
    numFragments::Int,
    fragment::Int
)
    fragment +=1
    binaryPayload = frame.inf[:binaryPayload]
    endIndex = Int(self.config.fragmentationThreshold)

    if length(binaryPayload) > endIndex
        partialPayload = splice!(binaryPayload, 1:endIndex)
    else
        partialPayload = binaryPayload
    end
    partframe = WebsocketFrame(self.config, self.buffers, partialPayload)
    if fragment === 1
        partframe.inf[:opcode] = frame.inf[:opcode]
    else
        partframe.inf[:opcode] = CONTINUATION_FRAME
    end
    partframe.inf[:fin] = fragment === numFragments
    sendFrame(self, partframe)
    fragment < numFragments && fragmentAndSend(self, frame, numFragments, fragment)
end
function fragmentAndSend(self::WebsocketConnection, frame::WebsocketFrame)
    @debug "WebsocketConnection.fragmentAndSend"
    threshold = self.config.fragmentationThreshold
    len = length(frame.inf[:binaryPayload])
    if !self.config.fragmentOutgoingMessages || len <= threshold
        frame.inf[:fin] = true
        sendFrame(self, frame)
        return
    end
    numFragments = Int(ceil(len / threshold))
    fragmentAndSend(self, frame, numFragments, 0)
end

function sendFrame(self::WebsocketConnection, frame::WebsocketFrame)
    @debug "WebsocketConnection.sendFrame"
    frame.inf[:mask] = self.config.maskOutgoingPackets
    !toBuffer(frame) && return
    outBuffer = self.buffers.outBuffer
    isopen(self.io[:stream]) && write(self.io[:stream], outBuffer)
end
# End send data

# Receive data
function processReceivedData(self::WebsocketConnection)
    frame = self.io[:currentFrame]
    inBuffer = self.buffers.inBuffer

    continued = addData(frame)

    @debug "processRecievedData" (;
        continued = continued,
        ptr = inBuffer.ptr,
        buffersize = inBuffer.size,
        parseState = frame.inf[:parseState],
        opcode = frame.inf[:opcode],
        length = frame.inf[:length],
        fin = frame.inf[:fin]
    )...

    !continued && return

    processFrame(self, frame)
    self.io[:currentFrame] = WebsocketFrame(
        self.config,
        self.buffers;
            ptr = frame.inf[:ptr]
    )

    if (inBuffer.ptr - 1) < inBuffer.size     
        processReceivedData(self)
    else
        self.io[:currentFrame].inf[:ptr] = 1
        isopen(inBuffer) && truncate(inBuffer, 0)
    end
end

function processFrame(self::WebsocketConnection, frame::WebsocketFrame)
    inf = frame.inf
    opcode = inf[:opcode]
    fragmentBuffer = self.buffers.fragmentBuffer
    binary = self.config.binary
    data = inf[:binaryPayload]
    if fragmentBuffer.size > 0 && (opcode > 0x00 && opcode < 0x08)
        throw(error("illegal frame opcode $opcode received in middle of fragmented message."))
    end

    if opcode === TEXT_FRAME || opcode === BINARY_FRAME       
        if frame.inf[:fin]
            callback = self.callbacks[:message]
            callback isa Function && callback(binary ? data : String(data))
        else
            unsafe_write(fragmentBuffer, pointer(data), length(data))
        end
    elseif opcode === CONTINUATION_FRAME
        unsafe_write(fragmentBuffer, pointer(data), length(data))
        if inf[:fin] 
            seekstart(fragmentBuffer)
            data = binary ? read(fragmentBuffer) : read(fragmentBuffer, String)
            isopen(fragmentBuffer) && truncate(fragmentBuffer, 0)
            callback = self.callbacks[:message]
            callback isa Function && callback(data)           
        end
        
    elseif opcode === PING_FRAME
        pong(self, inf[:binaryPayload])
    elseif opcode === PONG_FRAME
        callback = self.callbacks[:pong]
        if callback isa Function
            callback(binary ? frame.inf[:binaryPayload] : String(frame.inf[:binaryPayload]))
        end
    elseif opcode === CONNECTION_CLOSE_FRAME
        description = String(inf[:binaryPayload])
        
        if length(description) === 0
            
            if haskey(CLOSE_DESCRIPTIONS, inf[:closeStatus])
                description = CLOSE_DESCRIPTIONS[inf[:closeStatus]]
            else 
                description = "Unknown close code"
            end
        end
        
        self.io[:closeReason] = Closereason(inf[:closeStatus], description)
        if self.io[:closeTimeout] isa Timer && isopen(self.io[:closeTimeout])
            close(self.io[:closeTimeout])
        end
        isopen(self.io[:stream]) && close(self.io[:stream])
    end
end
# End receive data


