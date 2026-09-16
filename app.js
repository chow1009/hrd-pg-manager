
const data = window.HRD_DATA;
const state = {property:data.properties[0]||'', search:'', view:'dashboard'};

const $ = s => document.querySelector(s);
const money = n => '₹' + Number(n||0).toLocaleString('en-IN',{maximumFractionDigits:0});
const esc = s => String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));

function current(){
  const q=state.search.trim().toLowerCase();
  return data.tenants.filter(t=>
    t.property===state.property &&
    (!q || [t.name,t.room_no,t.bed,t.phone].join(' ').toLowerCase().includes(q))
  );
}
function allProperty(){return data.tenants.filter(t=>t.property===state.property)}

function renderCards(){
  const a=allProperty(), active=a.filter(t=>t.active);
  const dues=active.reduce((s,t)=>s+Number(t.dues||0),0);
  const collection=active.reduce((s,t)=>s+Number(t.collection||0),0);
  const rent=active.reduce((s,t)=>s+Number(t.rent||0),0);
  $('#cards').innerHTML=[
    ['Tenants',active.length],['Monthly Rent',money(rent)],['Pending Dues',money(dues)],['Collection',money(collection)]
  ].map(x=>`<div class="card"><div class="label">${x[0]}</div><div class="value">${x[1]}</div></div>`).join('');
}
function tenantRows(list){
  if(!list.length)return '<div class="empty">No tenants found.</div>';
  return `<div class="list">${list.map(t=>`
    <div class="row">
      <div><b>${esc(t.name||'Unnamed')}</b><div class="muted">${esc(t.room_no||'-')} • Bed ${esc(t.bed||'-')} • ${esc(t.phone||'')}</div></div>
      <div style="text-align:right"><div class="money">${money(t.rent)}</div>
      <div class="${Number(t.dues||0)>0?'danger':'ok'}">${Number(t.dues||0)>0?money(t.dues)+' due':'Clear'}</div></div>
    </div>`).join('')}</div>`;
}
function render(){
  renderCards();
  document.querySelectorAll('.tab').forEach(b=>b.classList.toggle('active',b.dataset.view===state.view));
  const list=current();
  if(state.view==='dashboard'){
    const due=[...allProperty()].filter(t=>Number(t.dues||0)>0).sort((a,b)=>b.dues-a.dues).slice(0,10);
    $('#content').innerHTML=`
      <div class="panel"><h2>Quick summary</h2>
        <div class="muted">Showing ${allProperty().length} imported tenant records for ${esc(state.property)}.</div>
      </div>
      <div class="panel"><h2>Top pending dues</h2>${tenantRows(due)}</div>`;
  }else if(state.view==='tenants'){
    $('#content').innerHTML=`<div class="panel"><h2>Tenants (${list.length})</h2>${tenantRows(list)}</div>`;
  }else{
    const due=list.filter(t=>Number(t.dues||0)>0).sort((a,b)=>b.dues-a.dues);
    $('#content').innerHTML=`<div class="panel"><h2>Pending dues (${due.length})</h2>${tenantRows(due)}</div>`;
  }
}
$('#property').innerHTML=data.properties.map(p=>`<option>${esc(p)}</option>`).join('');
$('#property').value=state.property;
$('#property').onchange=e=>{state.property=e.target.value;render()};
$('#search').oninput=e=>{state.search=e.target.value;render()};
document.querySelectorAll('.tab').forEach(b=>b.onclick=()=>{state.view=b.dataset.view;render()});

let deferred;
window.addEventListener('beforeinstallprompt',e=>{e.preventDefault();deferred=e;$('#installBtn').classList.remove('hidden')});
$('#installBtn').onclick=async()=>{if(!deferred)return;deferred.prompt();deferred=null};

if('serviceWorker' in navigator) navigator.serviceWorker.register('./sw.js').catch(()=>{});
render();
