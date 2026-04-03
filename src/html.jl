function write_interactive_html(infos::Vector{FunctionInfo}, outfile::AbstractString; title::AbstractString="FuncDeps Interactive Graph", target::Union{Nothing,AbstractString}=nothing, depth::Int=1)
    idx = build_index(infos)
    subinfos = infos
    if target !== nothing
        t = String(target)
        keep = Set([t])
        union!(keep, reachable_from(idx, t; direction=:forward, depth=depth))
        union!(keep, reachable_from(idx, t; direction=:reverse, depth=depth))
        subinfos = subgraph_infos(idx, collect(keep))
    end

    node_names, edges = _graph_nodes_edges(subinfos)
    modules = sort!(unique(module_of(n) for n in node_names))
    cmap = _module_color_map(modules)

    nodes_json = join([
        "{\"id\":\"$(_json_escape(n))\",\"label\":\"$(_json_escape(_short_label(n)))\",\"full\":\"$(_json_escape(n))\",\"module\":\"$(_json_escape(module_of(n)))\",\"color\":\"$(_json_escape(cmap[module_of(n)]))\"}"
        for n in node_names
    ], ",\n")

    edges_json = join([
        "{\"source\":\"$(_json_escape(src))\",\"target\":\"$(_json_escape(dst))\",\"kind\":\"$((module_of(src)==module_of(dst)) ? "internal" : "cross")\"}"
        for (src,dst) in edges
    ], ",\n")

    open(outfile, "w") do io
        write(io, _html_template(String(title), nodes_json, edges_json, target === nothing ? "" : String(target)))
    end
end

function _html_template(title::String, nodes_json::String, edges_json::String, target::String)
    return """
<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\" />
<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\" />
<title>$(title)</title>
<script src=\"https://unpkg.com/cytoscape/dist/cytoscape.min.js\"></script>
<style>
body { margin:0; font-family:Arial, Helvetica, sans-serif; display:grid; grid-template-columns: 320px 1fr; height:100vh; }
#sidebar { border-right:1px solid #ddd; padding:14px; overflow:auto; background:#fafafa; }
#cy { width:100%; height:100%; }
input, select, button { width:100%; margin:6px 0 10px; padding:8px; box-sizing:border-box; }
.card { background:white; border:1px solid #ddd; border-radius:8px; padding:10px; margin-top:10px; }
.small { font-size:12px; color:#555; }
.legend-row { display:flex; align-items:center; gap:8px; margin:4px 0; }
.swatch { width:14px; height:14px; border:1px solid #999; border-radius:3px; }
code { font-size:12px; }
</style>
</head>
<body>
<div id=\"sidebar\">
  <h2 style=\"margin-top:0\">FuncDeps</h2>
  <div class=\"small\">Interactive dependency graph</div>
  <label>Search</label>
  <input id=\"search\" placeholder=\"Type function name...\" />
  <label>Filter by module</label>
  <select id=\"moduleFilter\"><option value=\"\">All modules</option></select>
  <button id=\"fitBtn\">Fit graph</button>
  <button id=\"resetBtn\">Reset highlight</button>
  <div class=\"card\">
    <div><strong>Selected node</strong></div>
    <div id=\"selectedName\" class=\"small\">None</div>
    <div class=\"small\" id=\"selectedModule\"></div>
    <div style=\"margin-top:8px\"><strong>Callers</strong></div>
    <div id=\"callerList\" class=\"small\"></div>
    <div style=\"margin-top:8px\"><strong>Callees</strong></div>
    <div id=\"calleeList\" class=\"small\"></div>
  </div>
  <div class=\"card\">
    <div><strong>Legend</strong></div>
    <div class=\"small\">Node colors = module membership</div>
    <div class=\"small\">Blue edges = cross-module, gray edges = same-module</div>
    <div id=\"legendBox\"></div>
  </div>
</div>
<div id=\"cy\"></div>
<script>
const nodes = [$(nodes_json)];
const edges = [$(edges_json)];
const startTarget = $(isempty(target) ? "null" : "\"$(replace(target, "\"" => "\\\""))\"");

const moduleSet = [...new Set(nodes.map(n => n.module))].sort();
const moduleFilter = document.getElementById('moduleFilter');
const legendBox = document.getElementById('legendBox');
moduleSet.forEach(m => {
  const opt = document.createElement('option');
  opt.value = m; opt.textContent = m; moduleFilter.appendChild(opt);
  const row = document.createElement('div'); row.className = 'legend-row';
  const sw = document.createElement('div'); sw.className = 'swatch'; sw.style.background = nodes.find(n => n.module === m).color;
  const txt = document.createElement('div'); txt.textContent = m; txt.className = 'small';
  row.appendChild(sw); row.appendChild(txt); legendBox.appendChild(row);
});

const cy = cytoscape({
  container: document.getElementById('cy'),
  elements: [
    ...nodes.map(n => ({ data: n })),
    ...edges.map(e => ({ data: { id: e.source + '->' + e.target, source: e.source, target: e.target, kind: e.kind } }))
  ],
  style: [
    { selector: 'node', style: {
      'label': 'data(label)',
      'background-color': 'data(color)',
      'border-width': 1.5,
      'border-color': '#475569',
      'font-size': 10,
      'text-wrap': 'wrap',
      'text-max-width': 120,
      'width': 'label',
      'height': 'label',
      'padding': '8px'
    }},
    { selector: 'edge', style: {
      'curve-style': 'bezier',
      'target-arrow-shape': 'triangle',
      'line-color': '#94a3b8',
      'target-arrow-color': '#94a3b8',
      'width': 1.2,
      'opacity': 0.7
    }},
    { selector: 'edge[kind = "cross"]', style: {
      'line-color': '#2563eb',
      'target-arrow-color': '#2563eb',
      'width': 1.8,
      'opacity': 0.9
    }},
    { selector: '.dim', style: { 'opacity': 0.12 } },
    { selector: '.highlight', style: { 'border-color': '#dc2626', 'border-width': 3, 'opacity': 1 } },
    { selector: '.edge-highlight', style: { 'width': 3.2, 'opacity': 1 } }
  ],
  layout: { name: 'cose', animate: false, fit: true, padding: 30, idealEdgeLength: 90, nodeRepulsion: 7000 }
});

function clearHighlight() {
  cy.elements().removeClass('dim');
  cy.elements().removeClass('highlight');
  cy.elements().removeClass('edge-highlight');
}

function setSelected(node) {
  if (!node) {
    document.getElementById('selectedName').textContent = 'None';
    document.getElementById('selectedModule').textContent = '';
    document.getElementById('callerList').innerHTML = '';
    document.getElementById('calleeList').innerHTML = '';
    return;
  }
  const d = node.data();
  document.getElementById('selectedName').textContent = d.full;
  document.getElementById('selectedModule').textContent = 'Module: ' + d.module;
  const incoming = node.incomers('node').map(n => n.data('full')).sort();
  const outgoing = node.outgoers('node').map(n => n.data('full')).sort();
  document.getElementById('callerList').innerHTML = incoming.length ? incoming.map(x => '<div><code>' + x + '</code></div>').join('') : '<div>None</div>';
document.getElementById('calleeList').innerHTML = outgoing.length ? outgoing.map(x => '<div><code>' + x + '</code></div>').join('') : '<div>None</div>';
}

function highlightNeighborhood(node) {
  clearHighlight();
  const hood = node.closedNeighborhood();
  cy.elements().difference(hood).addClass('dim');
  node.addClass('highlight');
  node.connectedEdges().addClass('edge-highlight');
  node.incomers('node').addClass('highlight');
  node.outgoers('node').addClass('highlight');
  setSelected(node);
}

cy.on('tap', 'node', evt => highlightNeighborhood(evt.target));
cy.on('tap', evt => { if (evt.target === cy) { clearHighlight(); setSelected(null); } });

document.getElementById('search').addEventListener('input', e => {
  const q = e.target.value.trim().toLowerCase();
  if (!q) { clearHighlight(); setSelected(null); return; }
  const match = cy.nodes().filter(n => n.data('full').toLowerCase().includes(q) || n.data('label').toLowerCase().includes(q)).first();
  if (match.nonempty()) {
    highlightNeighborhood(match);
    cy.fit(match.closedNeighborhood(), 60);
  }
});

moduleFilter.addEventListener('change', e => {
  const mod = e.target.value;
  clearHighlight();
  if (!mod) return;
  const keep = cy.nodes().filter(n => n.data('module') === mod);
  cy.elements().difference(keep.union(keep.connectedEdges()).union(keep.connectedEdges().connectedNodes())).addClass('dim');
  cy.fit(keep.union(keep.connectedEdges()).union(keep.connectedEdges().connectedNodes()), 60);
});

document.getElementById('fitBtn').addEventListener('click', () => cy.fit(cy.elements(), 40));
document.getElementById('resetBtn').addEventListener('click', () => { document.getElementById('search').value = ''; moduleFilter.value = ''; clearHighlight(); setSelected(null); cy.fit(cy.elements(), 40); });

if (startTarget) {
  const n = cy.getElementById(startTarget);
  if (n.nonempty()) {
    highlightNeighborhood(n);
    cy.fit(n.closedNeighborhood(), 60);
  }
}
</script>
</body>
</html>
"""
end

_json_escape(s::AbstractString) = replace(String(s), "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n", "\r" => "")
