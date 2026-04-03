struct FunctionDef
    module_name::String
    function_name::String
    full_name::String
    file::String
end

struct FunctionInfo
    module_name::String
    function_name::String
    full_name::String
    file::String
    calls::Vector{String}
end

struct GraphIndex
    infos::Dict{String,FunctionInfo}
    callers::Dict{String,Vector{String}}
    callees::Dict{String,Vector{String}}
end
