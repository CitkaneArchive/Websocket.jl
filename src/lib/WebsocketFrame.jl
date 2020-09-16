struct WebsocketFrame
    maskBytes::IOBuffer
    frameHeader::IOBuffer
    binaryPayload::Array{UInt8, 1}
    flags::Dict{Symbol, Any}

    function WebsocketFrame(
        maskBytes::IOBuffer,
        frameHeader::IOBuffer,
        binaryPayload::Array{UInt8, 1} = Array{UInt8, 1}();
        kwargs...
    )
        kwargs = Dict{Symbol, Any}(kwargs)
        flags = Dict{Symbol, Any}(
            :fin => false,
            :mask => false,
            :opcode => 0x00
        )
        merge!(flags, kwargs)
        new(
            maskBytes,
            frameHeader,
            binaryPayload,
            flags
        )
    end
end

function toBuffer(frame::WebsocketFrame)
    headerLength = 2
    firstByte = 0x00
    secondByte = 0x00
    len = 0
    flags = (; frame.flags...)

    flags.fin && (firstByte |= 0x80)
    flags.mask && (secondByte |= 0x80)
    firstByte |= (flags.opcode & 0x0F)

    if flags.opcode === CONNECTION_CLOSE_FRAME
        throw(error("TODO"))
    else
        len = length(frame.binaryPayload)
    end

    if len <= 125
        secondByte |= (len & 0x7F)
    elseif len > 125 && len <= 0xFFFF
        secondByte |= 126
        headerLength += 2
    elseif len > 0xFFFF
        secondByte |= 127
        headerLength += 8
    end

    size = len + headerLength + (flags.mask ? 4 : 0)
    output = IOBuffer(Array{UInt8, 1}(undef, size);
        maxsize = size,
        read = true,
        write = true
    )
    header = [UInt8(firstByte), UInt8(secondByte)]
    write(output, header)

    if len > 125 && len <= 0xFFFF

    elseif len > 0xFFFF

    end

    if flags.mask
        maskKey = newMask()
        seek(frame.maskBytes, 0)
        write(frame.maskBytes, maskKey)
        write(output, maskKey)
        mask!(maskKey, frame.binaryPayload)
        write(output, frame.binaryPayload)
    elseif len > 0

    end
    seek(output, 0)
    output
end
