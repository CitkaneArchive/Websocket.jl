include("WebsocketFrame.jl")

struct WebsocketConnection
    io::HTTP.Streams.Stream
    maskBytes::IOBuffer
    frameHeader::IOBuffer
    bufferList
    currentFrame::WebsocketFrame

    function WebsocketConnection(
        io::HTTP.Streams.Stream,
        dataIn::Channel,
        dataOut::Channel
    )
        @debug "WebsocketConnection"
        maskBytes = IOBuffer(Array{UInt8, 1}(undef, 4); maxsize = 4, write = true, read =true)
        frameHeader = IOBuffer(Array{UInt8, 1}(undef, 10); maxsize = 10, write = true, read = true)
        self = new(
            io,
            maskBytes,
            frameHeader,
            [],
            WebsocketFrame(maskBytes, frameHeader)
        )
        @async_err begin
            for data in dataOut
                send(self, data)
            end
        end
        @async_err begin
            for data in dataIn
                handleSocketData(self, data)
            end
        end
        self
    end
end

function send(self::WebsocketConnection, data::String)
    @debug "WebsocketConnection.send"
    frame = WebsocketFrame(self.maskBytes, self.frameHeader, textbuffer(data))
    frame.flags[:opcode] = TEXT_FRAME
    fragmentAndSend(self, frame)
end

function fragmentAndSend(self::WebsocketConnection, frame::WebsocketFrame)
    @debug "WebsocketConnection.fragmentAndSend"
    frame.flags[:fin] = true
    sendFrame(self, frame)  
end

function sendFrame(self::WebsocketConnection, frame::WebsocketFrame)
    @debug "WebsocketConnection.sendFrame"
    frame.flags[:mask] = true
    data = toBuffer(frame)
    write(self.io, read(data))
    close(data)
end

function handleSocketData(self::WebsocketConnection, data::Array{UInt8,1})   
    push!(self.bufferList, data)
    processReceivedData(self)    
end

function processReceivedData(self::WebsocketConnection)
    @show self.bufferList
    #frame = self.currentFrame
    #frame.addData(self.bufferList)
end

function processFrame(frame::WebsocketFrame)
    @show frame.flags[:opcode]
end


