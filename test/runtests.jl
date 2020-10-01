using Websocket
using Test

@testset "Websocket.jl" begin
    @testset "Unit Tests" begin
        include("unittests.jl")
    end
end
