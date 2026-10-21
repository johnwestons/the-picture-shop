const $=id=>document.getElementById(id);
let engine,paused=false,last=0,lastRender=0,metadata,history=[],imageReady=false;
const machine=new Image();machine.src='assets/folder.png';machine.onload=()=>{imageReady=true;if(engine)render();};
const keys={q:'fold_down',w:'fold_up',a:'guide_down',s:'guide_up',e:'air',r:'proof',f:'start_stop',g:'refill','1':'speed_down','2':'speed_up',' ':'catch',b:'box',c:'clear_jam',n:'reset',v:'rotate_view'};
function available(r,a){
  if(a==='reset'||a==='rotate_view')return true;
  if(r.phase==='complete')return false;
  if(a==='catch')return r.delivery>0&&r.held<6&&r.boxingRemaining===0;
  if(a==='box')return r.boxingRemaining===0&&r.held>0&&(r.held===6||(r.fed===r.target&&!r.inTransit.length&&!r.delivery));
  if(a==='clear_jam')return r.phase==='jammed';
  if(a==='refill')return r.stock<8&&r.fed+r.stock<r.target;
  if(a==='start_stop')return r.phase==='running'||(['setup','paused'].includes(r.phase)&&r.proof);
  if(['fold_down','fold_up','guide_down','guide_up','air','proof'].includes(a))return !['running','jammed'].includes(r.phase);
  return true;
}
function act(action){
  if(!engine||!available(engine.state(),action))return;
  const accepted=engine.action(action);
  if(action==='reset'){history=[];paused=false;last=0;}
  history.push({at:Math.round(engine.state().time*100)/100,action,accepted});if(history.length>500)history.shift();
  render();
  if(action==='reset')openOrder();
}
function render(){
  const r=engine.state();document.body.className=r.phase;
  $('order-name').textContent=r.orderName;
  $('job-number').textContent=`WORK ORDER ${r.orderNumber}`;
  $('ticket-number').textContent=r.orderNumber;$('work-order-title').textContent=r.orderName;
  $('ticket-stock').textContent=r.stockName;
  let settingsMatch=true;
  for(const [key,target] of [['fold','targetFold'],['guide','targetGuide'],['air','targetAir']]){
    const matched=r[key]===r[target];settingsMatch=settingsMatch&&matched;
    $('ticket-'+key).textContent=r[target];
    $('ticket-'+key+'-current').textContent=`${r[key]} ${matched?'✓':'— adjust'}`;
    $('ticket-'+key+'-current').className=matched?'matched':'needs-setting';
  }
  $('check-settings').classList.toggle('done',settingsMatch);$('check-proof').classList.toggle('done',r.proof);
  $('order-targets').textContent=`Fold stop ${r.targetFold} · Guides ${r.targetGuide} · Air ${r.targetAir}`;
  for(const [key,target] of [['fold','targetFold'],['guide','targetGuide'],['air','targetAir']])$(key+'-target').textContent=`target ${r[target]}`;
  $('score').textContent=r.score;$('combo').textContent=r.combo;$('perfect').textContent=r.perfectCatches;
  $('run-mode').textContent=r.assisted?'Assisted setup':'Manual setup';
  const good=r.delivery>0&&r.oldestAge>=.25&&r.oldestAge<=1.1;
  let hint=r.delivery?(good?'CATCH NOW · timing bonus':r.oldestAge<.25?'Let the sheet settle…':'Ready · standard catch'):'Waiting for a folded piece';
  if(r.held===6)hint='Stack full · box these six';
  if(r.boxingRemaining>0)hint=`Packing · ${r.boxingRemaining.toFixed(1)}s`;
  if(r.phase==='jammed')hint='Clear jam, then run a new proof';
  if(r.phase==='complete')hint=r.rating;
  $('timing-hint').textContent=hint;$('timing-hint').classList.toggle('perfect',good&&r.held<6&&!r.boxingRemaining);
  $('timing-needle').style.left=`${Math.min(100,r.oldestAge/1.6*100)}%`;
  $('timing-needle').style.opacity=r.delivery?'1':'0';
  $('catch-result').textContent=r.catchFlash>0?r.lastCatch:'\u00a0';
  $('pressure').value=r.delivery;$('pressure-label').textContent=`Delivery ${r.delivery} / 6${r.delivery>=4?' · filling up!':''}`;
  $('mobile-hint').textContent=`${r.delivery}/6 delivery · ${hint}`;
  $('mobile-feed').textContent=r.phase==='running'?'Stop feeder':'Start feeder';
  for(const key of ['fold','guide','air','speed','stock','delivery','held','boxes','boxed','jams','spoiled'])$(key).textContent=r[key];
  $('transit').textContent=r.inTransit.length;$('phase').textContent=paused?'TEST PAUSED':r.phase.toUpperCase();
  $('message').textContent=r.message;$('progress').textContent=`${r.boxed} / ${r.target} BOXED`;
  $('proof').textContent=r.proof?'✓ Proof approved':'Proof needed';$('proof').classList.toggle('approved',r.proof);
  $('view').textContent=`VIEW ${String(r.view).padStart(2,'0')} / 08`;
  $('start').innerHTML=(r.phase==='running'?'Stop feeder':'Start run')+' <kbd>F</kbd>';
  $('pause').textContent=paused?'Resume test':'Pause test';
  $('stack').replaceChildren(...Array.from({length:r.held},()=>{const e=document.createElement('div');e.className='sheet';return e;}));
  $('stack').setAttribute('aria-label',`${r.held} of 6 pieces held`);
  document.querySelectorAll('[data-action]').forEach(b=>b.disabled=!available(r,b.dataset.action));
  $('setup').disabled=r.phase==='running'||r.phase==='jammed'||r.phase==='complete';
  $('step1').classList.toggle('active',!r.proof);$('step2').classList.toggle('active',r.phase==='running');$('step3').classList.toggle('active',r.delivery>0||r.held>0||r.phase==='complete');
  if(imageReady){
    const canvas=$('machine'),ctx=canvas.getContext('2d');ctx.clearRect(0,0,680,480);
    const edges=[0,444,887,1331,1774],col=(r.view-1)%4,row=Math.floor((r.view-1)/4),w=edges[col+1]-edges[col],h=row?443:444;
    ctx.drawImage(machine,edges[col],row?444:0,w,h,110,10,460,460);
  }
}
function frame(now){
  if(last&&engine&&!paused&&!document.hidden&&!$('work-order').open){
    let remaining=Math.min(.5,(now-last)/1000);
    while(remaining>0){const step=Math.min(.05,remaining);engine.tick(step);remaining-=step;}
  }
  last=now;if(engine&&now-lastRender>80){render();lastRender=now;}
  requestAnimationFrame(frame);
}
document.addEventListener('click',event=>{const button=event.target.closest('[data-action]');if(button&&!button.disabled)act(button.dataset.action);});
document.addEventListener('keydown',event=>{
  if($('work-order').open)return;
  if(event.repeat||event.ctrlKey||event.metaKey||event.altKey||['INPUT','TEXTAREA','SELECT'].includes(event.target.tagName))return;
  // Space on a focused button retains native keyboard activation.
  if(event.key===' '&&event.target.tagName==='BUTTON')return;
  if(keys[event.key.toLowerCase()]){event.preventDefault();act(keys[event.key.toLowerCase()]);}
});
document.addEventListener('visibilitychange',()=>{last=0;});
$('pause').onclick=()=>{paused=!paused;last=0;render();};
function openOrder(){if(engine&&!$('work-order').open){render();last=0;$('work-order').showModal();}}
function closeOrder(){$('work-order').close();last=0;}
$('open-order').onclick=openOrder;$('close-order').onclick=closeOrder;$('use-order').onclick=closeOrder;
$('work-order').addEventListener('close',()=>{last=0;});
$('setup').onclick=()=>{
  act('assist_setup');
};
$('report').onclick=()=>{
  const payload={test:'Regal folder',createdAt:new Date().toISOString(),source:metadata,state:engine.state(),paused,actions:history};
  const url=URL.createObjectURL(new Blob([JSON.stringify(payload,null,2)],{type:'application/json'}));
  const a=document.createElement('a');a.href=url;a.download='regal-folder-test.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
};
(async()=>{
  try{
    const metaResponse=await fetch('source.json',{cache:'no-store'});
    if(!metaResponse.ok)throw Error('The work-order revision could not be loaded.');
    metadata=await metaResponse.json();
    const sourceResponse=await fetch(`folder.lua?revision=${metadata.sha256}`,{cache:'no-store'});
    if(!sourceResponse.ok)throw Error('The folder rules could not be loaded.');
    const source=await sourceResponse.text();
    const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(source));
    const hash=Array.from(new Uint8Array(digest),v=>v.toString(16).padStart(2,'0')).join('');
    if(hash!==metadata.sha256)throw Error('This test update is still loading. Please reload in a moment.');
    engine=new FolderEngine(source);$('pause').disabled=false;$('report').disabled=false;$('open-order').disabled=false;
    $('source').textContent=`${metadata.label||'Test rules'} · ${metadata.sha256.slice(0,12)} · test-page balance experiment`;
    render();requestAnimationFrame(frame);
  }catch(error){$('phase').textContent='LOAD ERROR';$('message').textContent=error.message+' Reload the page to try again.';}
})();
