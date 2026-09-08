TEMPLATE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>privesc path graph &middot; __SRC__</title>
<style>
  :root{
    --bg:#0b0f14; --panel:#121a23; --panel-2:#0e151d; --line:#1e2b38;
    --ink:#cdd8e4; --muted:#67788b; --dim:#425264;
    --start:#57d99a; --root:#ffd24d;
    --confirmed:#ff4d5e; --likely:#f0a726; --info:#3fb0ff;
    --mono:ui-monospace,"JetBrains Mono","Cascadia Code","SFMono-Regular",Menlo,Consolas,monospace;
    --sans:"Inter",system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
  }
  *{box-sizing:border-box}
  html,body{margin:0;height:100%;background:var(--bg);color:var(--ink);font-family:var(--sans)}
  #app{display:grid;grid-template-rows:auto 1fr;height:100vh}

  header{display:flex;align-items:center;gap:22px;padding:14px 20px;
    border-bottom:1px solid var(--line);background:linear-gradient(180deg,#101922,#0b0f14)}
  .brand{font-family:var(--mono);font-weight:600;letter-spacing:.5px;font-size:15px}
  .brand b{color:var(--confirmed)}
  .brand .src{color:var(--muted);font-weight:400}
  .counts{display:flex;gap:8px;margin-left:auto;font-family:var(--mono);font-size:12px}
  .pill{padding:4px 10px;border:1px solid var(--line);border-radius:999px;color:var(--muted)}
  .pill.hot{color:var(--confirmed);border-color:#3a1f27;background:#170e12}
  .pill.warm{color:var(--likely);border-color:#3a2f1a;background:#171208}
  .btns{display:flex;gap:6px}
  button{font-family:var(--mono);font-size:12px;color:var(--ink);background:var(--panel);
    border:1px solid var(--line);border-radius:7px;padding:6px 11px;cursor:pointer}
  button:hover{border-color:var(--dim);background:#17222d}

  main{display:grid;grid-template-columns:1fr 340px;min-height:0}
  #cy{position:absolute;inset:0;background:
     radial-gradient(1200px 500px at 20% 0%,#0f1720 0%,#0b0f14 60%)}
  aside{border-left:1px solid var(--line);background:var(--panel-2);overflow-y:auto}
  .aside-h{padding:13px 16px;border-bottom:1px solid var(--line);
    font-family:var(--mono);font-size:11px;letter-spacing:1.5px;text-transform:uppercase;color:var(--muted)}

  .path{padding:12px 16px;border-bottom:1px solid var(--line);cursor:pointer;transition:background .12s}
  .path:hover{background:#0f1821}
  .path.active{background:#13202b}
  .path .tag{font-family:var(--mono);font-size:10px;letter-spacing:1px;text-transform:uppercase;
    padding:2px 7px;border-radius:4px;display:inline-block;margin-bottom:7px}
  .tag.confirmed{color:#111;background:var(--confirmed)}
  .tag.likely{color:#111;background:var(--likely)}
  .tag.info{color:#111;background:var(--info)}
  .path .chain{font-family:var(--mono);font-size:12.5px;line-height:1.5;color:var(--ink)}
  .path .chain .arrow{color:var(--confirmed);padding:0 5px}
  .path .note{font-size:11.5px;color:var(--muted);margin-top:6px;line-height:1.5;
    font-family:var(--mono);word-break:break-word}
  .empty{padding:22px 16px;color:var(--muted);font-size:13px;line-height:1.6}
  .aside-h .hint{color:var(--dim);text-transform:none;letter-spacing:0;font-size:10px}
  #back{color:var(--info);text-decoration:none}
  #back:hover{text-decoration:underline}

  .detail-title{padding:16px 16px 4px;font-family:var(--mono);font-size:14px;font-weight:600;color:var(--ink)}
  .detail-sev{margin:0 16px 12px;font-family:var(--mono);font-size:10px;letter-spacing:1px;
    text-transform:uppercase;padding:2px 7px;border-radius:4px;display:inline-block}
  .detail-sev.confirmed{color:#111;background:var(--confirmed)}
  .detail-sev.likely{color:#111;background:var(--likely)}
  .detail-sev.info{color:#111;background:var(--info)}
  .detail-sev.start{color:#111;background:var(--start)}
  .detail-sev.root{color:#111;background:var(--root)}
  .detail-label{padding:14px 16px 4px;font-family:var(--mono);font-size:10px;letter-spacing:1.5px;
    text-transform:uppercase;color:var(--muted)}
  .detail-desc{padding:0 16px;font-size:13px;line-height:1.6;color:var(--ink)}
  .codewrap{margin:6px 16px 4px;position:relative}
  .code{background:#080c11;border:1px solid var(--line);border-radius:8px;padding:12px 12px;
    font-family:var(--mono);font-size:12px;line-height:1.6;color:#9fe6b8;white-space:pre-wrap;
    word-break:break-word}
  .copy{position:absolute;top:8px;right:8px;font-family:var(--mono);font-size:10px;
    color:var(--muted);background:#0e151d;border:1px solid var(--line);border-radius:5px;
    padding:3px 8px;cursor:pointer}
  .copy:hover{color:var(--ink);border-color:var(--dim)}
  .copy.ok{color:var(--start);border-color:#1f3a2a}
  .detail-ref{padding:10px 16px 20px}
  .detail-ref a{color:var(--info);font-family:var(--mono);font-size:11.5px;text-decoration:none;word-break:break-all}
  .detail-ref a:hover{text-decoration:underline}

  .legend{position:absolute;left:16px;bottom:14px;z-index:5;font-family:var(--mono);font-size:11px;
    background:rgba(11,15,20,.82);border:1px solid var(--line);border-radius:9px;padding:10px 12px;
    display:flex;gap:16px;color:var(--muted)}
  .legend i{width:22px;height:2px;display:inline-block;vertical-align:middle;margin-right:6px}
  .cywrap{position:relative;min-height:0}
</style>
</head>
<body>
<div id="app">
  <header>
    <div class="brand"><b>&#9679;</b> privesc&#8202;/&#8202;path&#8202;graph <span class="src">&nbsp;&larr; __SRC__</span></div>
    <div class="counts">
      <span class="pill hot">__CONFIRMED__ confirmed to root</span>
      <span class="pill warm">__LIKELY__ likely</span>
    </div>
    <div class="btns">
      <button id="zoomout" title="zoom out">&minus;</button>
      <button id="zoomin" title="zoom in">&plus;</button>
      <button id="fit">fit</button>
      <button id="modeBtn" title="toggle likely/info paths">show all</button>
      <button id="relayout">re-layout</button>
    </div>
  </header>
  <main>
    <div class="cywrap">
      <div id="cy"></div>
      <div class="legend">
        <span><i style="background:var(--confirmed)"></i>confirmed</span>
        <span><i style="background:var(--likely)"></i>likely</span>
        <span><i style="background:var(--info)"></i>info</span>
        <span><i style="background:var(--start)"></i>you</span>
        <span><i style="background:var(--root)"></i>root</span>
      </div>
    </div>
    <aside>
      <div id="pathsView">
        <div class="aside-h">attack paths &middot; weakest first &middot; <span class="hint">tip: click a node</span></div>
        <div id="paths"></div>
      </div>
      <div id="detailView" style="display:none">
        <div class="aside-h"><a id="back" href="#">&larr; back to paths</a></div>
        <div id="detail"></div>
      </div>
    </aside>
  </main>
</div>

<script>/*CYTO*/</script>
<script>/*DAGRE*/</script>
<script>/*CYDAGRE*/</script>
<script>
const G = __DATA__;
const SEV = {confirmed:"#ff4d5e", likely:"#f0a726", info:"#3fb0ff"};
const KIND = {start:"#57d99a", root:"#ffd24d"};

const elements = [];
for(const n of G.nodes){
  elements.push({data:{id:n.id, label:n.label, kind:n.kind,
    desc:n.desc||"", abuse:n.abuse||"", ref:n.ref||""}});
}
let eid=0;
for(const e of G.edges){
  elements.push({data:{id:"e"+(eid++), source:e.source, target:e.target,
    severity:e.severity, tech:e.tech}});
}

const cy = cytoscape({
  container: document.getElementById('cy'),
  elements,
  wheelSensitivity:0.5,
  minZoom:0.05, maxZoom:3,
  style:[
    {selector:'node', style:{
      'label':'data(label)','text-wrap':'wrap','text-valign':'center','text-halign':'center',
      'color':'#dde7f1','font-family':'ui-monospace,Menlo,monospace','font-size':'20px',
      'text-max-width':'170px','line-height':1.3,
      'background-color':'#16212c','border-width':1.5,'border-color':'#26374a',
      'shape':'round-rectangle','width':'label','height':'label',
      'padding':'16px'
    }},
    {selector:'node[kind="start"]', style:{
      'background-color':'#0f2419','border-color':'#57d99a','border-width':2,'color':'#8ff0bd',
      'font-weight':'bold','shape':'round-rectangle'}},
    {selector:'node[kind="root"]', style:{
      'background-color':'#2a2208','border-color':'#ffd24d','border-width':2.5,'color':'#ffe08a',
      'font-weight':'bold','shape':'round-rectangle'}},
    {selector:'node[kind="cve"]', style:{
      'background-color':'#241226','border-color':'#c77dff','color':'#e0b3ff','border-width':1.5,
      'shape':'round-rectangle'}},
    {selector:'edge', style:{
      'curve-style':'bezier','width':2,'target-arrow-shape':'triangle',
      'line-color':'#2a3a4b','target-arrow-color':'#2a3a4b','arrow-scale':1.1,
      'opacity':.9
    }},
    {selector:'edge[severity="confirmed"]', style:{
      'line-color':SEV.confirmed,'target-arrow-color':SEV.confirmed,'width':2.4}},
    {selector:'edge[severity="likely"]', style:{
      'line-color':SEV.likely,'target-arrow-color':SEV.likely,'width':1.8,'opacity':.8}},
    {selector:'edge[severity="info"]', style:{
      'line-color':SEV.info,'target-arrow-color':SEV.info,'width':1.5,'line-style':'dashed','opacity':.65}},
    {selector:'.dim', style:{'opacity':.06}},
    {selector:'.hi', style:{'opacity':1}},
    {selector:'edge.hi', style:{'width':3.5,'z-index':99,
      'label':'data(tech)','font-family':'ui-monospace,Menlo,monospace','font-size':'13px',
      'color':'#cdd8e4','text-rotation':'autorotate','text-background-color':'#0b0f14',
      'text-background-opacity':.9,'text-background-padding':'3px','text-max-width':'260px','text-wrap':'wrap'}},
    {selector:'node.hi', style:{'border-width':3}},
    {selector:'.faded', style:{'display':'none'}}
  ],
  layout:{name:'dagre', rankDir:'LR', nodeSep:55, rankSep:280, edgeSep:22, ranker:'tight-tree'}
});

function runLayout(){ cy.elements(':visible').layout({name:'dagre',rankDir:'LR',nodeSep:55,rankSep:280,edgeSep:22,ranker:'tight-tree'}).run(); }

// ---- path panel ----
const panel = document.getElementById('paths');
function labelOf(id){ const n=G.nodes.find(x=>x.id===id); return n?n.label.replace(/\n/g,' '):id; }

if(G.paths.length===0){
  panel.innerHTML = '<div class="empty">No path to root was matched from the LinPEAS output. '
    + 'That doesn\'t mean the box is safe &mdash; it means nothing in the current rulebook fired. '
    + 'Extend the rulebook, or feed richer LinPEAS output.</div>';
}else{
  G.paths.forEach((p,i)=>{
    const div=document.createElement('div');
    div.className='path'; div.dataset.i=i;
    const chain=p.hops.map(labelOf).join('<span class="arrow">&rarr;</span>');
    div.innerHTML =
      '<span class="tag '+p.severity+'">'+p.severity+'</span>'
      + '<div class="chain">'+chain+'</div>'
      + '<div class="note">'+ (p.summary||'') +'</div>';
    div.addEventListener('click',()=>highlight(p, div));
    panel.appendChild(div);
  });
}

function highlight(p, el){
  document.querySelectorAll('.path').forEach(x=>x.classList.remove('active'));
  if(el) el.classList.add('active');
  cy.elements().addClass('dim').removeClass('hi');
  for(let k=0;k<p.hops.length;k++){
    const node=cy.getElementById(p.hops[k]);
    node.removeClass('dim').addClass('hi');
    if(k>0){
      cy.edges().forEach(e=>{
        if(e.data('source')===p.hops[k-1] && e.data('target')===p.hops[k]){
          e.removeClass('dim').addClass('hi');
        }
      });
    }
  }
}
function clearHi(){ cy.elements().removeClass('dim hi');
  document.querySelectorAll('.path').forEach(x=>x.classList.remove('active')); }
cy.on('tap', (e)=>{ if(e.target===cy){ clearHi(); showPaths(); } });

// ---- node detail panel (BloodHound-style: what it is + how to abuse) ----
const pathsView=document.getElementById('pathsView');
const detailView=document.getElementById('detailView');
const detailBox=document.getElementById('detail');
document.getElementById('back').addEventListener('click',(ev)=>{ev.preventDefault();showPaths();});

function esc(s){return (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function nodeSeverity(node){
  const k=node.data('kind');
  if(k==='start') return 'start';
  if(k==='root') return 'root';
  let best='info';
  node.connectedEdges().forEach(e=>{
    const s=e.data('severity');
    if(s==='confirmed') best='confirmed';
    else if(s==='likely'&&best!=='confirmed') best='likely';
  });
  return best;
}
function showNode(node){
  const d=node.data(); const sev=nodeSeverity(node);
  const title=(d.label||'').replace(/\n/g,' ');
  let h='<div class="detail-title">'+esc(title)+'</div>';
  h+='<span class="detail-sev '+sev+'">'+sev+'</span>';
  if(d.desc){ h+='<div class="detail-label">what it is</div><div class="detail-desc">'+esc(d.desc)+'</div>'; }
  if(d.abuse){ h+='<div class="detail-label">how to abuse it</div>'
    +'<div class="codewrap"><button class="copy">copy</button><div class="code">'+esc(d.abuse)+'</div></div>'; }
  if(d.ref){ h+='<div class="detail-ref"><div class="detail-label" style="padding-left:0">reference</div>'
    +'<a href="'+esc(d.ref)+'" target="_blank" rel="noopener">'+esc(d.ref)+'</a></div>'; }
  detailBox.innerHTML=h;
  const cbtn=detailBox.querySelector('.copy');
  if(cbtn) cbtn.addEventListener('click',()=>copyText(d.abuse,cbtn));
  pathsView.style.display='none'; detailView.style.display='block';
  cy.elements().addClass('dim').removeClass('hi');
  node.removeClass('dim').addClass('hi');
  node.connectedEdges().removeClass('dim').addClass('hi').connectedNodes().removeClass('dim').addClass('hi');
}
function showPaths(){ detailView.style.display='none'; pathsView.style.display='block'; clearHi(); }
function copyText(text,btn){
  const done=()=>{btn.textContent='copied';btn.classList.add('ok');
    setTimeout(()=>{btn.textContent='copy';btn.classList.remove('ok');},1200);};
  try{
    if(navigator.clipboard&&navigator.clipboard.writeText)
      navigator.clipboard.writeText(text).then(done,()=>fallbackCopy(text,done));
    else fallbackCopy(text,done);
  }catch(e){ fallbackCopy(text,done); }
}
function fallbackCopy(text,done){
  const ta=document.createElement('textarea');ta.value=text;
  ta.style.position='fixed';ta.style.opacity='0';document.body.appendChild(ta);ta.select();
  try{document.execCommand('copy');done();}catch(e){} document.body.removeChild(ta);
}
cy.on('tap','node',(e)=>{ showNode(e.target); });

// ---- controls ----
function zoomBy(factor){
  const z=cy.zoom()*factor;
  cy.zoom({level:z, renderedPosition:{x:cy.width()/2, y:cy.height()/2}});
}
document.getElementById('zoomin').onclick=()=>zoomBy(1.3);
document.getElementById('zoomout').onclick=()=>zoomBy(1/1.3);
document.getElementById('fit').onclick=()=>{cy.resize();cy.fit(50);};
document.getElementById('relayout').onclick=()=>{clearHi();runLayout();setTimeout(()=>{cy.resize();cy.fit(50);},130);};

// mode: start clean (confirmed only), toggle to reveal likely + info
let showAll=false;
function applyMode(){
  if(showAll){
    cy.elements().removeClass('faded');
  }else{
    // hide anything not on a confirmed edge
    cy.elements().addClass('faded');
    const keep=cy.collection();
    cy.edges('[severity="confirmed"]').forEach(e=>{
      keep.merge(e); keep.merge(e.source()); keep.merge(e.target());
    });
    keep.removeClass('faded');
  }
  runLayout(); setTimeout(()=>{cy.resize();cy.fit(50);},130);
}
document.getElementById('modeBtn').onclick=(ev)=>{
  showAll=!showAll;
  ev.target.textContent = showAll ? 'confirmed only' : 'show all';
  clearHi(); applyMode();
};

function fitAll(){ cy.resize(); cy.fit(50); }
window.addEventListener('resize', ()=>cy.resize());
setTimeout(()=>{ applyMode(); }, 180);
</script>
</body>
</html>
"""