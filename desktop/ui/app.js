const $ = id => document.getElementById(id);
const invoke = (command, args) => window.__TAURI__.core.invoke(command, args);
const names = {pro:'Pro 20x',prolite:'Pro 5x',promax:'Pro 50x',plus:'Plus'};
let busy=false, authenticating=false, last=null, next=0, stale=false;
function resetText(){
 const at=last?.rate_limit?.primary_window?.reset_at;
 if(!at) return '重置 —';
 const m=Math.ceil((at*1000-Date.now())/60000);
 if(m<=0)return '待重置';
 return m>=1440?`重置 ${Math.floor(m/1440)}天${Math.floor(m%1440/60)}时`:`重置 ${Math.floor(m/60)}时${m%60}分`;
}
function render(){
 $('reset').textContent=resetText();
 $('plan').textContent=names[last?.plan_type]||last?.plan_type||'—';
 const value=last?.rate_limit?.primary_window?.used_percent;
 $('remaining').textContent=typeof value==='number'?`${Math.round(Math.max(0,Math.min(100,100-value)))}%${stale?'*':''}`:'—';
 $('remaining').hidden=!last;
 $('login').hidden=!!last&&!authenticating;
 $('refresh').disabled=busy||authenticating;
}
async function refresh(){
 if(busy||authenticating)return;
 busy=true;render();
 try{last=await invoke('usage');stale=false;next=Date.now()+120000;$('island').title='已同步 · 剩余额度';}
 catch(e){stale=true;next=Date.now()+900000;$('island').title=String(e);if(String(e).includes('登录')){$('login').hidden=false;}}
 finally{busy=false;render();if(stale)$('login').hidden=false;}
}
$('refresh').onclick=refresh;
$('login').onclick=async()=>{
 if(authenticating)return;
 authenticating=true;render();$('login').textContent='授权中';
 try{
  const code=await invoke('login_start');
  $('login').textContent=code;$('login').title='在官方授权页输入此码，请勿分享';
  let done=false;while(!done&&authenticating)done=await invoke('login_poll');
  if(done){last=null;authenticating=false;await refresh();}
 }catch(e){$('island').title=String(e);}
 finally{authenticating=false;$('login').textContent='登录';render();}
};
const theme=localStorage.getItem('theme')||'dark';
if([...$('theme').options].some(o=>o.value===theme))$('theme').value=theme;
$('island').dataset.theme=$('theme').value;
$('theme').onchange=()=>{const t=$('theme').value;$('island').dataset.theme=t;localStorage.setItem('theme',t);};
$('island').oncontextmenu=async e=>{e.preventDefault();await invoke('menu_size',{expanded:true});$('menu').showModal();};
async function closeMenu(){ $('menu').close();await invoke('menu_size',{expanded:false}); }
$('close').onclick=closeMenu;
$('menu').oncancel=()=>invoke('menu_size',{expanded:false});
$('logout').onclick=async()=>{
 if(authenticating){$('island').title='请先完成授权或重新启动应用';return;}
 if(!confirm('删除本应用登录文件并退出账号？'))return;
 try{await invoke('logout');last=null;next=Date.now()+900000;render();await closeMenu();}catch(e){$('island').title=String(e);}
};
setInterval(()=>{render();if(Date.now()>=next)refresh();},15000);
refresh();
