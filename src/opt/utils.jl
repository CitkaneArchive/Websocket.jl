using Base64

include("vars.jl")

struct WebsocketFatalError <: Exception
    err::ErrorException
    trace::Array
    function WebsocketFatalError(err::ErrorException)
        new(
            err,
            backtrace()
        )
    end
end

nonce() = base64encode(rand(UInt8, 16))

textbuffer(data::String)::Array{UInt8,1} = Array{UInt8,1}(codeunits(data))
textbuffer(data::Number)::Array{UInt8,1} = Array{UInt8,1}(codeunits(string(data)))
buffertext(data::Array{UInt8, 1})::String = transcode(String, copy(data))

modindex(i::Int, m::Int) = ((i-1) % m) + 1
newMask() = rand(UInt8, 4)
function mask!(_mask::Array{UInt8, 1}, data::Array{UInt8, 1})
    for (i, value) in enumerate(data)
       data[i] = value ⊻ _mask[modindex(i, length(_mask))]
    end
end

function makeHeaders()
    Dict(
        "Upgrade" => "websocket",
        "Connection" => "Upgrade",
        "Sec-WebSocket-Key" => nonce(),
        "Sec-WebSocket-Version" => "13"
    )
end
#=
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
=#
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


