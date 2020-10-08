push!(LOAD_PATH,"../src/")

using Documenter, Websocket

makedocs(
    sitename = "Websocket",
    format = Documenter.HTML(),
    modules = [Websocket],
    pages = [
        "Introduction" => "index.md",
        "Server" => [
            "Server Usage" => "WebsocketServer.md",
            "Server Options" => "ServerOptions.md",
        ],
        "Client" => [
            "Client Usage" => "WebsocketClient.md",
            "Client Options" => "ClientOptions.md",
        ],
        "Websocket Connection" => "WebsocketConnection.md",
        "Error handling" => "Errors.md",
        "Acknowledgments" => "Acknowledgments.md"
    ]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
deploydocs(
    repo = "github.com/citkane/Websocket.jl.git"
)
