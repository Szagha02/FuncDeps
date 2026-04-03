function build_index(infos::Vector{FunctionInfo})
    infomap = Dict(info.full_name => info for info in infos)
    callees = Dict{String,Vector{String}}()
    callers = Dict{String,Vector{String}}()

    for info in infos
        callees[info.full_name] = sort(unique(info.calls))
        get!(callers, info.full_name, String[])
    end
    for info in infos
        for callee in info.calls
            push!(get!(callers, callee, String[]), info.full_name)
        end
    end
    for k in keys(callers)
        callers[k] = sort(unique(callers[k]))
    end
    GraphIndex(infomap, callers, callees)
end

module_of(full_name::AbstractString) = begin
    parts = split(String(full_name), ".")
    length(parts) <= 1 ? "Unknown" : join(parts[1:end-1], ".")
end

callees_of(idx::GraphIndex, name::AbstractString) = get(idx.callees, String(name), String[])
callers_of(idx::GraphIndex, name::AbstractString) = get(idx.callers, String(name), String[])

cross_module_callees_of(idx::GraphIndex, name::AbstractString) = [c for c in callees_of(idx, name) if module_of(c) != module_of(String(name))]
cross_module_callers_of(idx::GraphIndex, name::AbstractString) = [c for c in callers_of(idx, name) if module_of(c) != module_of(String(name))]

function reachable_from(idx::GraphIndex, start::AbstractString; direction::Symbol=:forward, depth::Int=1)
    start = String(start)
    depth < 0 && error("depth must be nonnegative")
    neighbors = direction == :forward ? idx.callees : direction == :reverse ? idx.callers : error("direction must be :forward or :reverse")
    seen = Set([start])
    frontier = Set([start])
    for _ in 1:depth
        newfront = Set{String}()
        for node in frontier
            for nxt in get(neighbors, node, String[])
                if !(nxt in seen)
                    push!(seen, nxt)
                    push!(newfront, nxt)
                end
            end
        end
        frontier = newfront
        isempty(frontier) && break
    end
    delete!(seen, start)
    sort!(collect(seen))
end

function subgraph_infos(idx::GraphIndex, keep_nodes::Vector{String})
    keep = Set(keep_nodes)
    out = FunctionInfo[]
    for node in sort!(collect(keep))
        haskey(idx.infos, node) || continue
        info = idx.infos[node]
        calls = [c for c in info.calls if c in keep]
        push!(out, FunctionInfo(info.module_name, info.function_name, info.full_name, info.file, sort(unique(calls))))
    end
    out
end
