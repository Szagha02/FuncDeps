const DEFAULT_PALETTE = [
    "#dbeafe", "#fde68a", "#dcfce7", "#fce7f3", "#ede9fe",
    "#fee2e2", "#cffafe", "#fef3c7", "#e0f2fe", "#fae8ff",
]

write_dot(infos::Vector{FunctionInfo}, outfile::AbstractString; kwargs...) = write_full_dot(infos, outfile; kwargs...)

function write_full_dot(infos::Vector{FunctionInfo}, outfile::AbstractString; cluster_by_module::Bool=false, color_by_module::Bool=true, with_legend::Bool=true)
    node_names, edges = _graph_nodes_edges(infos)
    modules = sort!(unique(module_of(n) for n in node_names))
    cmap = _module_color_map(modules)
    open(outfile, "w") do io
        println(io, "digraph FuncDepsFull {")
        println(io, "  rankdir=LR;")
        println(io, "  graph [fontname=Helvetica, overlap=false, splines=line, outputorder=edgesfirst, pack=true, nodesep=0.25, ranksep=0.45, pad=0.2];")
        println(io, "  node [shape=box, fontsize=8, fontname=Helvetica, style=filled, margin=\"0.06,0.03\"];")
        println(io, "  edge [fontname=Helvetica, arrowsize=0.55];\n")
        _write_nodes(io, node_names, cmap; cluster_by_module=cluster_by_module, color_by_module=color_by_module)
        for (src,dst) in edges
            src_mod = module_of(src); dst_mod = module_of(dst)
            attrs = src == dst ? "color=\"#dc262699\", style=dashed, penwidth=0.8" : src_mod == dst_mod ? "color=\"#94a3b855\", penwidth=0.55" : "color=\"#2563ebbb\", penwidth=1.1"
            println(io, "  \"$(_escape_dot(src))\" -> \"$(_escape_dot(dst))\" [$attrs];")
        end
        with_legend && _write_basic_legend(io, modules, cmap)
        println(io, "}")
    end
end

function write_cross_module_dot(infos::Vector{FunctionInfo}, outfile::AbstractString; cluster_by_module::Bool=true, color_by_module::Bool=true, with_legend::Bool=true)
    edges = Set{Tuple{String,String}}(); nodes = Set{String}()
    for info in infos
        sm = module_of(info.full_name)
        for callee in info.calls
            dm = module_of(callee)
            if sm != dm
                push!(edges, (info.full_name, callee)); push!(nodes, info.full_name); push!(nodes, callee)
            end
        end
    end
    node_names = sort!(collect(nodes)); edge_list = sort!(collect(edges), by=x->(x[1],x[2])); modules = sort!(unique(module_of(n) for n in node_names)); cmap = _module_color_map(modules)
    open(outfile, "w") do io
        println(io, "digraph FuncDepsCrossModule {")
        println(io, "  rankdir=LR;")
        println(io, "  graph [fontname=Helvetica, overlap=false, splines=true, newrank=true, pack=true, nodesep=0.3, ranksep=0.55, pad=0.2];")
        println(io, "  node [shape=box, fontsize=9, fontname=Helvetica, style=filled, margin=\"0.08,0.04\"];")
        println(io, "  edge [fontname=Helvetica, arrowsize=0.65, color=\"#1d4ed8cc\", penwidth=1.25];\n")
        _write_nodes(io, node_names, cmap; cluster_by_module=cluster_by_module, color_by_module=color_by_module)
        for (src,dst) in edge_list
            println(io, "  \"$(_escape_dot(src))\" -> \"$(_escape_dot(dst))\";")
        end
        with_legend && _write_basic_legend(io, modules, cmap)
        println(io, "}")
    end
end

function write_module_dot(infos::Vector{FunctionInfo}, outfile::AbstractString; color_by_module::Bool=true, with_legend::Bool=true)
    mods = Set{String}(); edges = Set{Tuple{String,String}}()
    for info in infos
        sm = module_of(info.full_name); push!(mods, sm)
        for callee in info.calls
            dm = module_of(callee); push!(mods, dm); sm != dm && push!(edges, (sm, dm))
        end
    end
    modlist = sort!(collect(mods)); cmap = _module_color_map(modlist)
    open(outfile, "w") do io
        println(io, "digraph ModuleDeps {")
        println(io, "  rankdir=LR;")
        println(io, "  graph [fontname=Helvetica, overlap=false, splines=true, pack=true, nodesep=0.5, ranksep=0.8, pad=0.25];")
        println(io, "  node [shape=ellipse, fontsize=12, fontname=Helvetica, style=filled, margin=\"0.14,0.08\"];")
        println(io, "  edge [fontname=Helvetica, color=\"#334155\", penwidth=1.4, arrowsize=0.8];\n")
        for mod in modlist
            fill = color_by_module ? cmap[mod] : "white"
            println(io, "  \"$(_escape_dot(mod))\" [fillcolor=\"$(fill)\"];")
        end
        println(io)
        for (src,dst) in sort!(collect(edges), by=x->(x[1],x[2]))
            println(io, "  \"$(_escape_dot(src))\" -> \"$(_escape_dot(dst))\";")
        end
        with_legend && _write_module_only_legend(io, modlist, cmap)
        println(io, "}")
    end
end

function write_function_focus_dot(infos::Vector{FunctionInfo}, target::AbstractString, outfile::AbstractString; depth::Int=1, include_callers::Bool=true, include_callees::Bool=true, cluster_by_module::Bool=true, color_by_module::Bool=true, with_legend::Bool=true)
    idx = build_index(infos); target = String(target)
    keep = Set([target]); caller_nodes = Set{String}(); callee_nodes = Set{String}()
    if include_callers
        c = reachable_from(idx, target; direction=:reverse, depth=depth); union!(keep,c); union!(caller_nodes,c)
    end
    if include_callees
        c = reachable_from(idx, target; direction=:forward, depth=depth); union!(keep,c); union!(callee_nodes,c)
    end
    sub = subgraph_infos(idx, collect(keep)); node_names, edges = _graph_nodes_edges(sub); modules = sort!(unique(module_of(n) for n in node_names)); cmap = _module_color_map(modules)
    categories = Dict{String,Symbol}()
    for n in node_names
        categories[n] = n == target ? :target : (n in caller_nodes && n in callee_nodes ? :both : n in caller_nodes ? :caller : n in callee_nodes ? :callee : :neutral)
    end
    open(outfile, "w") do io
        println(io, "digraph FunctionFocus {")
        println(io, "  rankdir=LR;")
        println(io, "  graph [fontname=Helvetica, overlap=false, splines=true, outputorder=edgesfirst, pack=true, nodesep=0.35, ranksep=0.55, pad=0.25];")
        println(io, "  node [shape=box, fontsize=10, fontname=Helvetica, style=filled, margin=\"0.10,0.05\"];")
        println(io, "  edge [fontname=Helvetica, arrowsize=0.7];\n")
        _write_focus_nodes(io, node_names, cmap, categories; cluster_by_module=cluster_by_module, color_by_module=color_by_module, internal_modules=Set([module_of(target)]))
        for (src,dst) in edges
            attrs = src == target && dst != target ? "color=\"#2563eb\", penwidth=2.1" : dst == target && src != target ? "color=\"#ea580c\", penwidth=2.1" : src == target && dst == target ? "color=\"#dc2626\", style=dashed, penwidth=1.1" : module_of(src) != module_of(dst) ? "color=\"#475569cc\", penwidth=1.1" : "color=\"#94a3b880\", penwidth=0.8"
            println(io, "  \"$(_escape_dot(src))\" -> \"$(_escape_dot(dst))\" [$attrs];")
        end
        with_legend && _write_focus_legend(io, modules, cmap)
        println(io, "}")
    end
end

function write_module_focus_dot(infos::Vector{FunctionInfo}, target_module::AbstractString, outfile::AbstractString; include_cross_edges::Bool=true, color_by_module::Bool=true, with_legend::Bool=true)
    target_module = String(target_module); keep = Set{String}()
    for info in infos
        if module_of(info.full_name) == target_module
            push!(keep, info.full_name); include_cross_edges && union!(keep, info.calls)
        end
    end
    idx = build_index(infos); sub = subgraph_infos(idx, collect(keep)); node_names, edges = _graph_nodes_edges(sub); modules = sort!(unique(module_of(n) for n in node_names)); cmap = _module_color_map(modules); internal_nodes = Set([n for n in node_names if module_of(n) == target_module])
    open(outfile, "w") do io
        println(io, "digraph ModuleFocus {")
        println(io, "  rankdir=LR;")
        println(io, "  graph [fontname=Helvetica, overlap=false, splines=true, outputorder=edgesfirst, pack=true, nodesep=0.32, ranksep=0.5, pad=0.25];")
        println(io, "  node [shape=box, fontsize=9, fontname=Helvetica, margin=\"0.08,0.04\"];")
        println(io, "  edge [fontname=Helvetica, arrowsize=0.62];\n")
        _write_module_boundary_nodes(io, node_names, cmap, internal_nodes; cluster_by_module=true, color_by_module=color_by_module, target_module=target_module)
        for (src,dst) in edges
            attrs = (module_of(src) == target_module && module_of(dst) == target_module) ? "color=\"#0f766eaa\", penwidth=1.0" : module_of(src) != module_of(dst) ? "color=\"#2563ebcc\", penwidth=1.35" : "color=\"#94a3b866\", penwidth=0.7"
            println(io, "  \"$(_escape_dot(src))\" -> \"$(_escape_dot(dst))\" [$attrs];")
        end
        with_legend && _write_module_focus_legend(io, modules, cmap, target_module)
        println(io, "}")
    end
end

function write_file_focus_dot(infos::Vector{FunctionInfo}, file_query::AbstractString, outfile::AbstractString; include_cross_edges::Bool=true, color_by_module::Bool=true, with_legend::Bool=true)
    needle = lowercase(String(file_query)); keep = Set{String}(); matched_files = Set{String}()
    for info in infos
        if occursin(needle, lowercase(basename(info.file))) || occursin(needle, lowercase(info.file))
            push!(keep, info.full_name); push!(matched_files, info.file); include_cross_edges && union!(keep, info.calls)
        end
    end
    idx = build_index(infos); sub = subgraph_infos(idx, collect(keep)); node_names, edges = _graph_nodes_edges(sub); modules = sort!(unique(module_of(n) for n in node_names)); cmap = _module_color_map(modules); internal_nodes = Set([n for n in node_names if haskey(idx.infos, n) && (idx.infos[n].file in matched_files)])
    open(outfile, "w") do io
        println(io, "digraph FileFocus {")
        println(io, "  rankdir=LR;")
        println(io, "  graph [fontname=Helvetica, overlap=false, splines=true, outputorder=edgesfirst, pack=true, nodesep=0.32, ranksep=0.5, pad=0.25];")
        println(io, "  node [shape=box, fontsize=9, fontname=Helvetica, margin=\"0.08,0.04\"];")
        println(io, "  edge [fontname=Helvetica, arrowsize=0.62];\n")
        _write_file_boundary_nodes(io, node_names, cmap, internal_nodes; cluster_by_module=true, color_by_module=color_by_module)
        for (src,dst) in edges
            attrs = (src in internal_nodes && dst in internal_nodes) ? "color=\"#0f766eaa\", penwidth=1.0" : module_of(src) != module_of(dst) ? "color=\"#2563ebcc\", penwidth=1.35" : "color=\"#94a3b866\", penwidth=0.7"
            println(io, "  \"$(_escape_dot(src))\" -> \"$(_escape_dot(dst))\" [$attrs];")
        end
        with_legend && _write_file_focus_legend(io, modules, cmap)
        println(io, "}")
    end
end

function _graph_nodes_edges(infos::Vector{FunctionInfo})
    node_names = sort(unique(info.full_name for info in infos))
    edges = Set{Tuple{String,String}}()
    for info in infos, callee in info.calls
        push!(edges, (info.full_name, callee))
    end
    return node_names, sort!(collect(edges), by=x->(x[1],x[2]))
end

function _write_nodes(io, node_names, cmap; cluster_by_module::Bool, color_by_module::Bool)
    grouped = Dict{String,Vector{String}}()
    for node in node_names
        push!(get!(grouped, module_of(node), String[]), node)
    end
    if cluster_by_module
        for mod in sort!(collect(keys(grouped)))
            println(io, "  subgraph \"cluster_$(_safe_cluster_name(mod))\" {")
            println(io, "    label=\"$(_escape_dot(mod))\";")
            println(io, "    color=\"#94a3b8\";")
            println(io, "    style=rounded;")
            for node in sort!(grouped[mod])
                fill = color_by_module ? cmap[mod] : "white"
                println(io, "    \"$(_escape_dot(node))\" [fillcolor=\"$(fill)\", label=\"$(_escape_dot(_short_label(node)))\"];")
            end
            println(io, "  }\n")
        end
    else
        for node in sort(node_names)
            mod = module_of(node); fill = color_by_module ? cmap[mod] : "white"
            println(io, "  \"$(_escape_dot(node))\" [fillcolor=\"$(fill)\", label=\"$(_escape_dot(_short_label(node)))\"];")
        end
        println(io)
    end
end

function _write_focus_nodes(io, node_names, cmap, categories; cluster_by_module::Bool, color_by_module::Bool, internal_modules::Set{String})
    grouped = Dict{String,Vector{String}}(); for node in node_names push!(get!(grouped, module_of(node), String[]), node) end
    attrs_for(node) = begin
        mod = module_of(node); basefill = color_by_module ? cmap[mod] : "white"; cat = get(categories, node, :neutral)
        cat == :target ? "fillcolor=\"#fef2f2\", color=\"#dc2626\", penwidth=2.6, fontsize=12, label=\"$(_escape_dot(_short_label(node)))\"" :
        cat == :caller ? "fillcolor=\"#fff7ed\", color=\"#ea580c\", penwidth=1.8, label=\"$(_escape_dot(_short_label(node)))\"" :
        cat == :callee ? "fillcolor=\"#eff6ff\", color=\"#2563eb\", penwidth=1.8, label=\"$(_escape_dot(_short_label(node)))\"" :
        cat == :both ? "fillcolor=\"#f5f3ff\", color=\"#7c3aed\", penwidth=2.0, label=\"$(_escape_dot(_short_label(node)))\"" :
        !(mod in internal_modules) ? "fillcolor=\"white\", color=\"#64748b\", style=\"rounded,dashed\", penwidth=1.2, label=\"$(_escape_dot(_short_label(node)))\"" :
        "fillcolor=\"$(basefill)\", color=\"#64748b\", penwidth=1.0, label=\"$(_escape_dot(_short_label(node)))\""
    end
    if cluster_by_module
        for mod in sort!(collect(keys(grouped)))
            println(io, "  subgraph \"cluster_$(_safe_cluster_name(mod))\" {")
            println(io, "    label=\"$(_escape_dot(mod))\";")
            println(io, "    color=\"#cbd5e1\";")
            println(io, "    style=rounded;")
            for node in sort!(grouped[mod])
                println(io, "    \"$(_escape_dot(node))\" [", attrs_for(node), "];" )
            end
            println(io, "  }\n")
        end
    else
        for node in sort(node_names)
            println(io, "  \"$(_escape_dot(node))\" [", attrs_for(node), "];" )
        end
        println(io)
    end
end

function _write_module_boundary_nodes(io, node_names, cmap, internal_nodes; cluster_by_module::Bool, color_by_module::Bool, target_module::String)
    grouped = Dict{String,Vector{String}}(); for node in node_names push!(get!(grouped, module_of(node), String[]), node) end
    attrs_for(node) = begin mod=module_of(node); basefill=color_by_module ? cmap[mod] : "white"; node in internal_nodes ? "fillcolor=\"$(basefill)\", color=\"#0f766e\", style=filled, penwidth=1.5, label=\"$(_escape_dot(_short_label(node)))\"" : "fillcolor=\"white\", color=\"#475569\", style=\"rounded,dashed\", penwidth=1.2, label=\"$(_escape_dot(_short_label(node)))\"" end
    for mod in sort!(collect(keys(grouped)))
        border = mod == target_module ? "#0f766e" : "#cbd5e1"
        println(io, "  subgraph \"cluster_$(_safe_cluster_name(mod))\" {")
        println(io, "    label=\"$(_escape_dot(mod))\";")
        println(io, "    color=\"$(border)\";")
        println(io, "    style=rounded;")
        for node in sort!(grouped[mod])
            println(io, "    \"$(_escape_dot(node))\" [", attrs_for(node), "];" )
        end
        println(io, "  }\n")
    end
end

function _write_file_boundary_nodes(io, node_names, cmap, internal_nodes; cluster_by_module::Bool, color_by_module::Bool)
    grouped = Dict{String,Vector{String}}(); for node in node_names push!(get!(grouped, module_of(node), String[]), node) end
    attrs_for(node) = begin mod=module_of(node); basefill=color_by_module ? cmap[mod] : "white"; node in internal_nodes ? "fillcolor=\"$(basefill)\", color=\"#0f766e\", style=filled, penwidth=1.5, label=\"$(_escape_dot(_short_label(node)))\"" : "fillcolor=\"white\", color=\"#475569\", style=\"rounded,dashed\", penwidth=1.2, label=\"$(_escape_dot(_short_label(node)))\"" end
    for mod in sort!(collect(keys(grouped)))
        println(io, "  subgraph \"cluster_$(_safe_cluster_name(mod))\" {")
        println(io, "    label=\"$(_escape_dot(mod))\";")
        println(io, "    color=\"#cbd5e1\";")
        println(io, "    style=rounded;")
        for node in sort!(grouped[mod])
            println(io, "    \"$(_escape_dot(node))\" [", attrs_for(node), "];" )
        end
        println(io, "  }\n")
    end
end

function _write_basic_legend(io, modules, cmap)
    println(io, "\n  subgraph cluster_legend {")
    println(io, "    label=\"Legend\"; color=\"#cbd5e1\"; style=rounded; fontsize=10;")
    println(io, "    same_edge [label=\"same-module edge\", shape=plaintext];")
    println(io, "    cross_edge [label=\"cross-module edge\", shape=plaintext];")
    println(io, "    recur_edge [label=\"recursive edge\", shape=plaintext];")
    for mod in modules
        println(io, "    \"legend_$(_safe_cluster_name(mod))\" [label=\"$(_escape_dot(mod))\", shape=box, style=filled, fillcolor=\"$(cmap[mod])\"];")
    end
    println(io, "  }")
end

function _write_module_only_legend(io, mods, cmap)
    println(io, "\n  subgraph cluster_legend {")
    println(io, "    label=\"Legend\"; color=\"#cbd5e1\"; style=rounded;")
    for mod in mods
        println(io, "    \"legend_$(_safe_cluster_name(mod))\" [label=\"$(_escape_dot(mod))\", shape=ellipse, style=filled, fillcolor=\"$(cmap[mod])\"];")
    end
    println(io, "  }")
end

function _write_focus_legend(io, modules, cmap)
    println(io, "\n  subgraph cluster_legend {")
    println(io, "    label=\"Legend\"; color=\"#cbd5e1\"; style=rounded;")
    println(io, "    target_key [label=\"target\", shape=box, style=filled, fillcolor=\"#fef2f2\", color=\"#dc2626\"];")
    println(io, "    caller_key [label=\"caller\", shape=box, style=filled, fillcolor=\"#fff7ed\", color=\"#ea580c\"];")
    println(io, "    callee_key [label=\"callee\", shape=box, style=filled, fillcolor=\"#eff6ff\", color=\"#2563eb\"];")
    println(io, "    both_key [label=\"caller + callee\", shape=box, style=filled, fillcolor=\"#f5f3ff\", color=\"#7c3aed\"];")
    println(io, "    boundary_key [label=\"external boundary node\", shape=box, style=\"rounded,dashed\", fillcolor=\"white\", color=\"#64748b\"];")
    for mod in modules
        println(io, "    \"legend_$(_safe_cluster_name(mod))\" [label=\"$(_escape_dot(mod))\", shape=box, style=filled, fillcolor=\"$(cmap[mod])\"];")
    end
    println(io, "  }")
end

function _write_module_focus_legend(io, modules, cmap, target_module)
    internal_fill = get(cmap, target_module, "#dcfce7")

    println(io, "\n  subgraph cluster_legend {")
    println(io, "    label=\"Legend\"; color=\"#cbd5e1\"; style=rounded;")
    println(io, "    internal_key [label=\"inside $(_escape_dot(target_module))\", shape=box, style=filled, fillcolor=\"$(internal_fill)\", color=\"#0f766e\"];")
    println(io, "    boundary_key [label=\"external boundary node\", shape=box, style=\"rounded,dashed\", fillcolor=\"white\", color=\"#475569\"];")
    for mod in modules
        println(io, "    \"legend_$(_safe_cluster_name(mod))\" [label=\"$(_escape_dot(mod))\", shape=box, style=filled, fillcolor=\"$(cmap[mod])\"];")
    end
    println(io, "  }")
end

function _write_file_focus_legend(io, modules, cmap)
    println(io, "\n  subgraph cluster_legend {")
    println(io, "    label=\"Legend\"; color=\"#cbd5e1\"; style=rounded;")
    println(io, "    internal_key [label=\"matched file node\", shape=box, style=filled, fillcolor=\"#dcfce7\", color=\"#0f766e\"];")
    println(io, "    boundary_key [label=\"external boundary node\", shape=box, style=\"rounded,dashed\", fillcolor=\"white\", color=\"#475569\"];")
    for mod in modules
        println(io, "    \"legend_$(_safe_cluster_name(mod))\" [label=\"$(_escape_dot(mod))\", shape=box, style=filled, fillcolor=\"$(cmap[mod])\"];")
    end
    println(io, "  }")
end

_module_color_map(modules) = Dict(mod => DEFAULT_PALETTE[mod1(i, length(DEFAULT_PALETTE))] for (i,mod) in enumerate(sort!(collect(modules))))
_short_label(full_name::AbstractString) = split(String(full_name), ".")[end]
_safe_cluster_name(s::AbstractString) = replace(String(s), r"[^A-Za-z0-9_]+" => "_")
_escape_dot(s::AbstractString) = replace(String(s), "\"" => "\\\"")
