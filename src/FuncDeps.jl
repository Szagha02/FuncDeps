module FuncDeps

include("types.jl")
include("parse.jl")
include("query.jl")
include("graph.jl")
include("html.jl")

export FunctionDef, FunctionInfo, GraphIndex
export scan_project, build_index
export module_of, callers_of, callees_of, cross_module_callers_of, cross_module_callees_of, reachable_from
export write_dot, write_full_dot, write_cross_module_dot, write_module_dot
export write_function_focus_dot, write_module_focus_dot, write_file_focus_dot
export write_interactive_html

end