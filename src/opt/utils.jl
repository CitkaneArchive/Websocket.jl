struct WebsocketError <: Exception
    msg::String
end

requestHash() = base64encode(rand(UInt8, 16))
function acceptHash(key::String)
    hashkey = "$(key)258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    base64encode(digest(MD_SHA1, hashkey))
end

textbuffer(data::String)::Array{UInt8,1} = Array{UInt8,1}(data)
textbuffer(data::Number)::Array{UInt8,1} = Array{UInt8,1}(string(data))

modindex(i::Int, m::Int) = ((i-1) % m) + 1
function mask!(mask::IOBuffer, data::Array{UInt8, 1})
    for (i, value) in enumerate(data)
       data[i] = value ⊻ mask.data[modindex(i, mask.size)]
    end
end

function makeHeaders(extend::Dict{String, String})
    headers = Dict{String, String}(
        "Sec-WebSocket-Version" => defaultHeaders["Sec-WebSocket-Version"],
    )
    for (key, value) in extend
        headers[key] = value
    end
    headers["Upgrade"] = defaultHeaders["Upgrade"]
    headers["Connection"] = defaultHeaders["Connection"]
    headers["Sec-WebSocket-Key"] = requestHash()

    headers
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


