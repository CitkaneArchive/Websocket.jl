using Base64

const CONTINUATION_FRAME = UInt8(0)
const TEXT_FRAME = UInt8(1)
const BINARY_FRAME = UInt8(2)
const CONNECTION_CLOSE_FRAME = UInt8(8)
const PING_FRAME = UInt8(9)
const PONG_FRAME = UInt8(10)

# Connected, fully-open, ready to send and receive frames
const STATE_OPEN = "open"
# Received a close frame from the remote peer
const STATE_PEER_REQUESTED_CLOSE = "peer_requested_close"
# Sent close frame to remote peer.  No further data can be sent.
const STATE_ENDING = "ending"
# Connection is fully closed.  No further data can be sent or received.
const STATE_CLOSED = "closed"

nonce() = base64encode(rand(UInt8, 16))

#=
tobuffer(string::String) = Array{UInt8, 1}(string)
tobuffer(number::Number) = Array{UInt8, 1}(string(number))
tostring(data::Array{UInt8, 1}) = transcode(String, copy(data))
=#
textbuffer(data::String)::Array{UInt8,1} = convert(Array{UInt8,1}, transcode(UInt8, data))
textbuffer(data::Number)::Array{UInt8,1} = convert(Array{UInt8,1}, transcode(UInt8, string(data)))
buffertext(data::Array{UInt8, 1})::String = transcode(String, copy(data))

modindex(i::Int, m::Int) = ((i-1) % m) + 1
newMask() = rand(UInt8, 4)
function mask!(_mask::Array{UInt8, 1}, data::Array{UInt8, 1})
    for (i, value) in enumerate(data)
       data[i] = value ⊻ _mask[modindex(i, length(_mask))]
    end
end

macro async_err(fn)
    quote
        t = @async try
            eval($(esc(fn)))
        catch err
            bt = catch_backtrace()
            println()
            showerror(stderr, err, bt)
            println()
            exit()
        end
    end
end

function explain(object::Any)
    type = typeof(object)
    @show type
    println("----------------------------------")
    for field in fieldnames(type)
        value = getfield(object, field)
        println(field, " | ", typeof(value), " | ", value)
    end
    println("----------------------------------")
end


