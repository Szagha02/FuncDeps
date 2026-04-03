# FuncDeps.jl

FuncDeps.jl builds static dependency graphs for Julia source trees.

## Features

- Full function dependency graph
- Cross-module function dependency graph
- Module dependency graph
- Function focus graphs
- Module focus graphs
- File focus graphs
- Interactive HTML viewer
- Query helpers such as callers/callees lookup

## Install

```julia
using Pkg
Pkg.add(url="https://github.com/Szagha02/FuncDeps.jl")