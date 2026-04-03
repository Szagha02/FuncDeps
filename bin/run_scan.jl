#!/usr/bin/env julia

function parse_args(args)
    length(args) < 1 && error("Usage: julia --project=. bin/run_scan.jl <source_dir> [output_dir] [--module NAME] [--file NAME] [--function QUALIFIED] [--depth N] [--html] [--no-legend] [--no-color]")
    source_dir = args[1]
    i = 2
    output_dir = pwd()
    if i <= length(args) && !startswith(args[i], "--")
        output_dir = args[i]
        i += 1
    end
    opts = Dict{String,Any}(
        "module" => nothing,
        "file" => nothing,
        "function" => nothing,
        "depth" => 1,
        "with_legend" => true,
        "color_by_module" => true,
        "html" => false,
    )
    while i <= length(args)
        arg = args[i]
        if arg == "--module"
            i += 1; opts["module"] = args[i]
        elseif arg == "--file"
            i += 1; opts["file"] = args[i]
        elseif arg == "--function"
            i += 1; opts["function"] = args[i]
        elseif arg == "--depth"
            i += 1; opts["depth"] = parse(Int, args[i])
        elseif arg == "--no-legend"
            opts["with_legend"] = false
        elseif arg == "--no-color"
            opts["color_by_module"] = false
        elseif arg == "--html"
            opts["html"] = true
        else
            error("Unknown argument: $arg")
        end
        i += 1
    end
    return source_dir, output_dir, opts
end

source_dir, output_dir, opts = parse_args(ARGS)
isdir(output_dir) || mkpath(output_dir)

include(joinpath(@__DIR__, "..", "src", "FuncDeps.jl"))
using .FuncDeps

infos = scan_project(source_dir)
index = build_index(infos)

full_dot = joinpath(output_dir, "funcdeps_full.dot")
cross_dot = joinpath(output_dir, "funcdeps_cross_module.dot")
module_dot = joinpath(output_dir, "moduledeps.dot")

write_full_dot(infos, full_dot; cluster_by_module=false, color_by_module=opts["color_by_module"], with_legend=opts["with_legend"])
write_cross_module_dot(infos, cross_dot; cluster_by_module=true, color_by_module=opts["color_by_module"], with_legend=opts["with_legend"])
write_module_dot(infos, module_dot; color_by_module=opts["color_by_module"], with_legend=opts["with_legend"])

println("Wrote:")
println("  full function graph:      ", abspath(full_dot))
println("  cross-module func graph:  ", abspath(cross_dot))
println("  module graph:             ", abspath(module_dot))

if opts["function"] !== nothing
    out = joinpath(output_dir, "function_focus.dot")
    write_function_focus_dot(infos, opts["function"], out; depth=opts["depth"], cluster_by_module=true, color_by_module=opts["color_by_module"], with_legend=opts["with_legend"])
    println("  function focus graph:     ", abspath(out))
end
if opts["module"] !== nothing
    out = joinpath(output_dir, "module_focus.dot")
    write_module_focus_dot(infos, opts["module"], out; color_by_module=opts["color_by_module"], with_legend=opts["with_legend"])
    println("  module focus graph:       ", abspath(out))
end
if opts["file"] !== nothing
    out = joinpath(output_dir, "file_focus.dot")
    write_file_focus_dot(infos, opts["file"], out; color_by_module=opts["color_by_module"], with_legend=opts["with_legend"])
    println("  file focus graph:         ", abspath(out))
end
if opts["html"]
    out = joinpath(output_dir, "interactive_graph.html")
    write_interactive_html(infos, out; target=opts["function"], depth=opts["depth"])
    println("  interactive HTML viewer:  ", abspath(out))
end

println()
println("Functions found: ", length(infos))
println("Edges found: ", sum(length(info.calls) for info in infos))
println()
println("Sample exact function names:")
for name in first(sort([info.full_name for info in infos]), min(10, length(infos)))
    println("  ", name)
end
println()
println("Sample cross-module edges:")
let shown = 0
    for info in infos
        for callee in cross_module_callees_of(index, info.full_name)
            println("  ", info.full_name, " -> ", callee)
            shown += 1
            shown >= 10 && break
        end
        shown >= 10 && break
    end
    shown == 0 && println("  (no cross-module calls found)")
end
