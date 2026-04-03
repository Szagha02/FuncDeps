# FuncDeps.jl

Static dependency graphs for Julia source trees.

## Graph outputs

- `moduledeps.dot` — module architecture view
- `funcdeps_cross_module.dot` — exact cross-module function dependencies
- `funcdeps_full.dot` — full function dependency graph
- `function_focus.dot` / `module_focus.dot` / `file_focus.dot` — focused views
- `interactive_graph.html` — self-contained interactive browser viewer

## Quick start

```powershell
julia --project=. bin/run_scan.jl "C:\path\to\repo\src" --html
```

To generate a focused function graph and an interactive viewer centered on that function:

```powershell
julia --project=. bin/run_scan.jl "C:\path\to\repo\src" --function "Structs.fusion_ring" --depth 2 --html
```

## Render DOT files

```powershell
& "C:\Program Files\Graphviz\bin\dot.exe" -Tsvg moduledeps.dot -o moduledeps.svg
& "C:\Program Files\Graphviz\bin\dot.exe" -Tsvg funcdeps_cross_module.dot -o funcdeps_cross_module.svg
& "C:\Program Files\Graphviz\bin\sfdp.exe" -Goverlap=prism -Gsplines=line -Gpack=true -Grepulsiveforce=2 -Tsvg funcdeps_full.dot -o funcdeps_full.svg
& "C:\Program Files\Graphviz\bin\dot.exe" -Tsvg function_focus.dot -o function_focus.svg
```

## Interactive HTML viewer

Open `interactive_graph.html` directly in your browser. It supports:

- search
- zoom/pan
- click node to inspect callers/callees
- filter by module
- highlight neighborhoods

## Installing from github:

using Pkg
Pkg.add(url="https://github.com/Szagha02/FuncDeps.jl")
using FuncDeps

And then some sample runs:

infos = scan_project("C:/path/to/some/package/src")

write_module_dot(infos, "moduledeps.dot")

write_cross_module_dot(infos, "funcdeps_cross_module.dot")

write_full_dot(infos, "funcdeps_full.dot")

write_interactive_html(infos, "interactive_graph.html")

for focus views:

write_function_focus_dot(infos, "Structs.fusion_ring", "function_focus.dot"; depth=2)

write_module_focus_dot(infos, "Creation", "module_focus.dot")

write_file_focus_dot(infos, "ImportData.jl", "file_focus.dot")

## Basic Usage:

julia --project=. bin/run_scan.jl "C:\path\to\your\package\src"

This writes:
moduledeps.dot
funcdeps_cross_module.dot
funcdeps_full.dot

## To focus on a graph:

- Focusing on a function:

julia --project=. bin/run_scan.jl "C:\path\to\your\package\src" --function "Structs.fusion_ring" --depth 2

- Focusing on a module:

julia --project=. bin/run_scan.jl "C:\path\to\your\package\src" --module "Creation"

- Interactive HTML viewer:

julia --project=. bin/run_scan.jl "C:\path\to\your\package\src" --html

Then open:

interactive_graph.html

## Rendering DOT files with Graphviz:

dot -Tsvg moduledeps.dot -o moduledeps.svg
dot -Tsvg funcdeps_cross_module.dot -o funcdeps_cross_module.svg
sfdp -Goverlap=prism -Gsplines=line -Gpack=true -Grepulsiveforce=2 -Tsvg funcdeps_full.dot -o funcdeps_full.svg

For focusing graphs:

dot -Tsvg function_focus.dot -o function_focus.svg
dot -Tsvg module_focus.dot -o module_focus.svg
dot -Tsvg file_focus.dot -o file_focus.svg

moduledeps: which modules depend on which modules
funcdeps_cross_module: which functions call functions in other modules
funcdeps_full: all discovered internal function-to-function calls
focus graphs: smaller, readable views centered on one target

