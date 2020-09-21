struct WebsocketError <: Exception
    msg::String
end

requestHash() = base64encode(rand(UInt8, 16))
function acceptHash(key::String)
    hashkey = "$(key)258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    base64encode(digest(MD_SHA1, hashkey))
end

newBuffer(size::Int) = IOBuffer(Array{UInt8, 1}(undef, size); maxsize = size, write = true, read =true)


textbuffer(data::String)::Array{UInt8,1} = Array{UInt8,1}(codeunits(data))
textbuffer(data::Number)::Array{UInt8,1} = Array{UInt8,1}(codeunits(string(data)))
statusbuffer(status::Int) = reinterpret(UInt8, [hton(UInt16(status))])
statusint(data::Array{UInt8, 1})::Int = Int(ntoh(reinterpret(UInt16, data)[1]))
#buffertext(data::Array{UInt8, 1})::String = transcode(String, copy(data))


modindex(i::Int, m::Int) = ((i-1) % m) + 1
newMask() = rand(UInt8, 4)
function mask!(mask::Array{UInt8, 1}, data::Array{UInt8, 1})
    for (i, value) in enumerate(data)
       data[i] = value ⊻ mask[modindex(i, length(mask))]
    end
end

function makeConfig(overrides::NamedTuple)
    defaultConfig
end
function makeHeaders(extend::Dict{String, String})
    headers = Dict{String, String}(
        "Sec-WebSocket-Version" => "13",
    )
    for (key, value) in extend
        headers[key] = value
    end
    headers["Upgrade"] = "websocket"
    headers["Connection"] = "Upgrade"
    headers["Sec-WebSocket-Key"] = requestHash()

    headers
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


