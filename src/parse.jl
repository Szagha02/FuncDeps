const IGNORED_CALLEE_SYMBOLS = Set([
    Symbol("+"), Symbol("-"), Symbol("*"), Symbol("/"), Symbol("\\"),
    Symbol("^"), Symbol("%"), Symbol("//"),
    Symbol("<"), Symbol(">"), Symbol("<="), Symbol(">="),
    Symbol("=="), Symbol("!="), Symbol("!"), Symbol("~"),
    Symbol("&"), Symbol("|"), Symbol("⊻"), Symbol("&&"), Symbol("||"),
    Symbol("<<"), Symbol(">>"), Symbol(">>>"),
    :in, :∈, :isa, :colon, Symbol(":"),
    :getindex, :setindex!, :iterate,
    :return, :convert, :promote, :typeassert,
    :throw, :error,
])

const ALLOWED_NAME_RE = r"^[A-Za-z_][A-Za-z0-9_!]*$"

scan_project(root::AbstractString; strict::Bool=true) = _scan_project(String(root), strict)

function _scan_project(root::String, strict::Bool)
    isdir(root) || error("Input folder does not exist: $root")
    files = _jl_files(root)

    defs = FunctionDef[]
    for file in files
        ex = _parse_file(read(file, String), file)
        _collect_defs!(defs, ex, _default_module_name(file, root), file)
    end
    defs = _dedup_defs(defs)

    project_full_names = Set(d.full_name for d in defs)
    simple_to_full = Dict{String,Vector{String}}()
    for d in defs
        push!(get!(simple_to_full, d.function_name, String[]), d.full_name)
    end

    infos = FunctionInfo[]
    for file in files
        ex = _parse_file(read(file, String), file)
        _collect_infos!(infos, ex, _default_module_name(file, root), file, project_full_names, simple_to_full; strict=strict)
    end

    return _dedup_infos(infos)
end

function _jl_files(root::AbstractString)
    files = String[]
    for (dir, _, fs) in walkdir(root)
        for f in fs
            endswith(f, ".jl") || continue
            push!(files, joinpath(dir, f))
        end
    end
    sort!(files)
    return files
end

function _parse_file(src::String, file::String)
    try
        return Meta.parse("begin\n" * src * "\nend")
    catch err
        error("Could not parse $file\n$err")
    end
end

function _collect_defs!(defs::Vector{FunctionDef}, ex, modname::String, file::String)
    ex isa Expr || return
    if ex.head == :toplevel || ex.head == :block
        foreach(a -> _collect_defs!(defs, a, modname, file), ex.args)
        return
    elseif ex.head == :module
        newmod, body = _module_parts(ex, modname)
        _collect_defs!(defs, body, newmod, file)
        return
    elseif ex.head == :function
        fname = _function_name_from_signature(ex.args[1])
        _keep_function_name(fname) && push!(defs, FunctionDef(modname, fname, string(modname, ".", fname), file))
        return
    elseif ex.head == :(=)
        lhs = ex.args[1]
        if _is_short_function_lhs(lhs)
            fname = _function_name_from_signature(lhs)
            _keep_function_name(fname) && push!(defs, FunctionDef(modname, fname, string(modname, ".", fname), file))
        end
        return
    end
end

function _collect_infos!(infos::Vector{FunctionInfo}, ex, modname::String, file::String,
    project_full_names::Set{String}, simple_to_full::Dict{String,Vector{String}}; strict::Bool=true)
    ex isa Expr || return
    if ex.head == :toplevel || ex.head == :block
        foreach(a -> _collect_infos!(infos, a, modname, file, project_full_names, simple_to_full; strict=strict), ex.args)
        return
    elseif ex.head == :module
        newmod, body = _module_parts(ex, modname)
        _collect_infos!(infos, body, newmod, file, project_full_names, simple_to_full; strict=strict)
        return
    elseif ex.head == :function
        fname = _function_name_from_signature(ex.args[1])
        if _keep_function_name(fname)
            calls = String[]
            _collect_project_calls!(calls, ex.args[2], modname, project_full_names, simple_to_full; strict=strict)
            push!(infos, FunctionInfo(modname, fname, string(modname, ".", fname), file, sort(unique(calls))))
        end
        return
    elseif ex.head == :(=)
        lhs, rhs = ex.args
        if _is_short_function_lhs(lhs)
            fname = _function_name_from_signature(lhs)
            if _keep_function_name(fname)
                calls = String[]
                _collect_project_calls!(calls, rhs, modname, project_full_names, simple_to_full; strict=strict)
                push!(infos, FunctionInfo(modname, fname, string(modname, ".", fname), file, sort(unique(calls))))
            end
        end
        return
    end
end

function _collect_project_calls!(calls::Vector{String}, ex, current_module::String,
    project_full_names::Set{String}, simple_to_full::Dict{String,Vector{String}}; strict::Bool=true)
    ex isa Expr || return

    if ex.head == :call
        callee = _callee_name(ex.args[1])
        if callee !== nothing && _keep_callee_name(callee)
            if occursin('.', callee)
                callee in project_full_names && push!(calls, callee)
            else
                local_name = string(current_module, ".", callee)
                if local_name in project_full_names
                    push!(calls, local_name)
                elseif haskey(simple_to_full, callee)
                    candidates = simple_to_full[callee]
                    length(candidates) == 1 && push!(calls, candidates[1])
                elseif !strict
                    push!(calls, callee)
                end
            end
        end
    end

    foreach(a -> _collect_project_calls!(calls, a, current_module, project_full_names, simple_to_full; strict=strict), ex.args)
end

function _default_module_name(file::String, root::String)
    rel = relpath(file, root)
    parts = split(rel, Base.Filesystem.path_separator)
    if !isempty(parts)
        firstpart = parts[1]
        if firstpart == "src"
            return splitext(basename(root))[1]
        end
    end
    splitext(basename(file))[1]
end

function _module_parts(ex::Expr, parent_mod::String)
    if length(ex.args) >= 3
        name_expr = ex.args[end-1]
        body = ex.args[end]
        name = String(name_expr)
        newmod = parent_mod == "Main" ? name : (parent_mod == splitext(parent_mod)[1] ? name : string(parent_mod, ".", name))
        return newmod, body
    end
    return parent_mod, Expr(:block)
end

function _is_short_function_lhs(lhs)
    lhs isa Expr || return false
    lhs.head == :call && return true
    (lhs.head == :where || lhs.head == :(::)) && return _is_short_function_lhs(lhs.args[1])
    return false
end

function _function_name_from_signature(sig)
    if sig isa Symbol
        name = String(sig)
        return _valid_simple_name(name) ? name : nothing
    elseif sig isa Expr
        if sig.head == :call || sig.head == :where || sig.head == :(::)
            return _function_name_from_signature(sig.args[1])
        elseif sig.head == :(.)
            q = _qualified_name(sig)
            return q !== nothing && _keep_callee_name(q) ? q : nothing
        end
    end
    return nothing
end

function _qualified_name(ex)
    if ex isa Symbol
        return _valid_simple_name(String(ex)) ? String(ex) : nothing
    elseif ex isa QuoteNode
        return _valid_simple_name(String(ex.value)) ? String(ex.value) : nothing
    elseif ex isa Expr && ex.head == :(.)
        left = _qualified_name(ex.args[1])
        right = _qualified_name(ex.args[2])
        (left === nothing || right === nothing) && return nothing
        q = string(left, ".", right)
        parts = split(q, ".")
        return all(_valid_simple_name, parts) ? q : nothing
    end
    return nothing
end

function _callee_name(ex)
    if ex isa Symbol
        ex in IGNORED_CALLEE_SYMBOLS && return nothing
        name = String(ex)
        return _valid_simple_name(name) ? name : nothing
    elseif ex isa QuoteNode
        name = String(ex.value)
        return _valid_simple_name(name) ? name : nothing
    elseif ex isa Expr
        if ex.head == :(.)
            q = _qualified_name(ex)
            return q !== nothing && _keep_callee_name(q) ? q : nothing
        elseif ex.head == :(::) || ex.head == :where
            return _callee_name(ex.args[1])
        end
    end
    return nothing
end

_keep_function_name(fname) = fname !== nothing && !isempty(fname) && !startswith(fname, "#")

_valid_simple_name(name::AbstractString) = occursin(ALLOWED_NAME_RE, String(name))

function _keep_callee_name(name::AbstractString)
    s = String(name)
    isempty(s) && return false
    startswith(s, "#") && return false
    parts = split(s, ".")
    all(_valid_simple_name, parts) || return false
    simple = parts[end]
    occursin(r"^[A-Z_][A-Z0-9_]*$", simple) && return false
    return true
end

function _dedup_defs(defs::Vector{FunctionDef})
    seen = Set{String}()
    out = FunctionDef[]
    for d in defs
        d.full_name in seen && continue
        push!(out, d)
        push!(seen, d.full_name)
    end
    out
end

function _dedup_infos(infos::Vector{FunctionInfo})
    merged = Dict{String,FunctionInfo}()
    for info in infos
        if haskey(merged, info.full_name)
            old = merged[info.full_name]
            merged[info.full_name] = FunctionInfo(old.module_name, old.function_name, old.full_name, old.file, sort(unique(vcat(old.calls, info.calls))))
        else
            merged[info.full_name] = FunctionInfo(info.module_name, info.function_name, info.full_name, info.file, sort(unique(info.calls)))
        end
    end
    sort!(collect(values(merged)), by=x->x.full_name)
end
