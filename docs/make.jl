using Documenter
using FuncDeps

makedocs(
    sitename = "FuncDeps.jl",
    modules = [FuncDeps],
    format = Documenter.HTML(),
    pages = [
        "Home" => "index.md",
        "API" => "api.md",
    ],
)

deploydocs(
    repo = "github.com/Szagha02/FuncDeps.jl.git",
    devbranch = "main",
)