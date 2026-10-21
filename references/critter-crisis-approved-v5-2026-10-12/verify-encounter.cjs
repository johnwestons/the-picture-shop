const vm=require('vm'),fs=require('fs'),path=require('path'),assert=require('assert');
const results=[];
function harness(){
  const elements=new Map();let callbacks=[],clock=0,drawCalls=[];
  const ctx=new Proxy({drawImage(...args){drawCalls.push(args);}}, {get:(o,k)=>['createLinearGradient','createRadialGradient'].includes(k)?()=>({addColorStop(){}}):o[k]||(()=>{}),set:(o,k,v)=>(o[k]=v,true)});
  const make=key=>({dataset:{},style:{},textContent:'',hidden:false,disabled:false,attrs:{},handlers:{},classList:{toggle(){}},
    setAttribute(k,v){this.attrs[k]=String(v);},addEventListener(k,f){(this.handlers[k]??=[]).push(f);},
    getBoundingClientRect(){return key==='.cc-wheel'?{left:0,top:0,width:100,height:100}:{left:0,top:0,width:736,height:460};},
    getContext(){return ctx;},setPointerCapture(){},
    dispatch(type,event={}){for(const f of this.handlers[type]||[])f({preventDefault(){},pointerId:1,detail:1,...event});}
  });
  const root=make('root');root.querySelector=k=>{if(!elements.has(k))elements.set(k,make(k));return elements.get(k);};root.querySelectorAll=()=>[];
  const context={document:{getElementById:()=>root,addEventListener(){},hidden:false},window:{addEventListener(){}},matchMedia:()=>({matches:false}),ResizeObserver:class{observe(){}},Image:class{constructor(){this.naturalWidth=1374;this.width=1374;this.height=1145;}},devicePixelRatio:1,requestAnimationFrame:f=>callbacks.push(f),console};context.globalThis=context;
  let code=fs.readFileSync(path.join(__dirname,'encounter-preview.js'),'utf8').replace('__CC_ASSET_DATA__','{"atlas":"test","boat":"test","boatScene":"test","gun":"test"}');
  code=code.replace(/\}\)\(\);\s*$/,'globalThis.qa={S,selectScene,geometry,posture,coverSpots,weapons,targets:()=>targets,enemies:()=>enemies,pickups:()=>pickupTargets,drops:()=>pickups};})();');
  vm.runInNewContext(code,context);
  const frames=n=>{for(let i=0;i<n;i++){clock+=1000/60;const current=callbacks;callbacks=[];current.forEach(f=>f(clock));}};
  context.qa.selectScene('boat',false);frames(2);
  return {root,el:k=>root.querySelector(k),frames,qa:context.qa,drawCalls:()=>drawCalls,clearDrawCalls:()=>{drawCalls=[];}};
}
function aimAt(h,t){h.el('canvas').dispatch('pointermove',{pointerType:'mouse',clientX:t.x,clientY:t.y});}
function shotAt(h,t){aimAt(h,t);h.el('canvas').dispatch('pointerdown',{pointerType:'mouse'});h.el('canvas').dispatch('pointerup');}
function defeatTo(h,count){let limit=1500;while(h.qa.S.hits<count&&--limit>0){h.frames(3);const target=h.qa.targets().find(t=>h.qa.enemies()[t.id].alive);if(target)shotAt(h,target);if(h.qa.S.ammo===0){h.el('.cc-cover').dispatch('pointerdown');h.frames(70);h.el('.cc-cover').dispatch('pointerup');h.frames(20);}}assert.equal(h.qa.S.hits,count,'Must reach defeat milestone');}
{
 const h=harness();assert.equal(h.qa.drops().length,0,'No free guns on scene entry');h.el('.cc-play').dispatch('click');defeatTo(h,2);assert.equal(h.qa.drops().length,0,'Must earn 3 defeats');defeatTo(h,3);assert.equal(h.qa.drops().length,1);assert.equal(h.qa.drops()[0].kind,'smg');assert.equal(h.qa.S.weapon,'pistol','Earning does not auto-equip');h.frames(50);
 const smg=h.qa.pickups().find(t=>t.pickup.kind==='smg');aimAt(h,smg);h.frames(20);assert.equal(h.qa.S.weapon,'pistol','Aiming alone must not collect a gun');
 h.el('.cc-cover').dispatch('pointerdown');h.frames(30);shotAt(h,smg);assert.equal(h.qa.S.weapon,'pistol','No pickup through cover');h.el('.cc-cover').dispatch('pointerup');h.frames(30);
 shotAt(h,{x:368,y:100});assert.equal(h.qa.S.weapon,'pistol','Miss does not equip');h.frames(20);shotAt(h,h.qa.pickups().find(t=>t.pickup.kind==='smg'));assert.equal(h.qa.S.weapon,'smg');assert.equal(h.qa.S.ammo,30);assert(!smg.pickup.alive);
 h.frames(20);aimAt(h,{x:368,y:95});h.el('.cc-fire').dispatch('pointerdown');h.frames(60);h.el('.cc-fire').dispatch('pointerup');assert(h.qa.S.ammo<=18&&h.qa.S.ammo>=16,'SMG fires continuously around 12.5 rounds/s');const released=h.qa.S.ammo;h.frames(30);assert.equal(h.qa.S.ammo,released,'Release immediately stops firing');
 h.el('canvas').dispatch('pointerdown',{pointerType:'mouse'});h.frames(30);h.el('canvas').dispatch('pointerup');assert(h.qa.S.ammo<=released-6,'Mouse hold also fires full auto');
 h.el('.cc-cover').dispatch('pointerdown');h.frames(65);assert.equal(h.qa.S.ammo,30);h.el('.cc-cover').dispatch('pointerup');h.frames(30);
 defeatTo(h,5);assert.equal(h.qa.drops().length,1,'No shotgun until six defeats');defeatTo(h,6);assert.equal(h.qa.drops().length,2);assert.equal(h.qa.S.phase,'reward','Clear gives time to shoot earned reward');h.frames(50);
 shotAt(h,h.qa.pickups().find(t=>t.pickup.kind==='shotgun'));assert.equal(h.qa.S.weapon,'shotgun');assert.equal(h.qa.S.ammo,6);assert(!h.qa.pickups().find(t=>t.pickup.kind==='shotgun').pickup.alive);
 h.frames(110);assert.equal(h.qa.S.area,2);assert.equal(h.qa.drops().length,2,'Area advance never spawns free or duplicate guns');shotAt(h,{x:368,y:100});assert.equal(h.qa.S.ammo,5);h.frames(12);shotAt(h,{x:368,y:100});assert.equal(h.qa.S.ammo,5,'Shotgun must have slower follow-up');h.el('.cc-cover').dispatch('pointerdown');h.frames(70);assert.equal(h.qa.S.ammo,6);
 results.push('SMG earned only after 3 defeats; shotgun only after 6; animated rewards still require shooting to equip');results.push('SMG holds full-auto fire on touch FIRE and mouse, stops on release; shotgun has slower follow-up and per-weapon reload');
 h.qa.selectScene('yard',false);assert.equal(h.qa.drops().length,0,'Replay resets earned rewards');results.push('Rewards carry between areas without duplication and reset for a new encounter');
}
{
 const h=harness();h.el('.cc-play').dispatch('click');defeatTo(h,3);h.frames(50);shotAt(h,h.qa.pickups().find(t=>t.pickup.kind==='smg'));h.frames(20);aimAt(h,{x:368,y:85});
 h.el('canvas').dispatch('pointerdown',{pointerType:'mouse'});h.frames(210);assert.equal(h.qa.S.ammo,0,'Held SMG empties its magazine without more clicks');h.frames(30);assert.equal(h.qa.S.ammo,0,'Empty magazine never becomes negative');h.el('canvas').dispatch('pointercancel');assert(!h.qa.S.fireHeld,'Canceled mouse input cannot leave auto fire stuck');
 h.el('.cc-cover').dispatch('pointerdown');h.frames(65);h.el('.cc-cover').dispatch('pointerup');h.frames(30);assert.equal(h.qa.S.ammo,30);
 h.root.dispatch('keydown',{code:'KeyF'});h.frames(30);h.root.dispatch('keyup',{code:'KeyF'});assert(h.qa.S.ammo<25,'Held keyboard F also supports full auto');const afterRelease=h.qa.S.ammo;h.frames(20);assert.equal(h.qa.S.ammo,afterRelease);results.push('SMG fires an entire magazine on one hold, stops at zero, and releases safely on cancellation and keyboard key-up');
}
{
 const h=harness();h.qa.selectScene('boat',false);h.clearDrawCalls();h.frames(2);assert(!h.drawCalls().some(a=>a.length===9&&a[1]===1100&&a[2]===937),'Boat must never draw crate sprites');
 h.el('.cc-play').dispatch('click');h.frames(75);const ducked=h.qa.enemies().filter(e=>h.qa.posture(e).duck>=.6);assert(ducked.length>0);for(const e of ducked)assert(!h.qa.targets().some(t=>t.id===e.id),'Crouched boat enemies must be protected by hull');
 h.el('.cc-cover').dispatch('pointerdown');h.clearDrawCalls();h.frames(50);assert(!h.drawCalls().some(a=>a.length===9&&a[1]===1100&&a[2]===937),'Player boat cover must also be crate-free');
 h.qa.selectScene('yard',false);h.clearDrawCalls();h.frames(2);assert(h.drawCalls().some(a=>a.length===9&&a[1]===1100&&a[2]===937),'Land cover stays in place');results.push('Boat characters and player use no crates; crouched enemies have no exposed hit target; land crates retained');
}
{
 const h=harness(),wheel=h.el('.cc-wheel');wheel.dispatch('pointerdown',{clientX:80,clientY:50});h.frames(30);assert(h.qa.S.aimX>.65);wheel.dispatch('pointerup');const stopped=h.qa.S.aimX;h.frames(30);assert.equal(h.qa.S.aimX,stopped);results.push('Aim wheel moves continuously while held and stops on release');
 h.el('.cc-fire').dispatch('pointerdown');h.el('.cc-fire').dispatch('pointerup');assert.equal(h.qa.S.ammo,11);
 h.el('.cc-cover').dispatch('pointerdown');h.frames(50);assert.equal(h.qa.S.ammo,12);assert(h.qa.S.duck>.98);assert(h.el('.cc-fire').disabled);
 h.frames(600);assert.equal(h.qa.S.health,100);results.push('Cover automatically reloads and blocks incoming damage');
 h.el('.cc-cover').dispatch('pointerup');h.frames(480);assert(h.qa.S.health<100);results.push('Exposed player takes damage after enemy wind-up');
}
for(const scene of ['yard','reactor','docks']){
 const h=harness();h.qa.selectScene(scene,false);h.frames(2);const fixed=JSON.stringify(h.qa.coverSpots());assert.equal(h.qa.targets().length,0,'Land enemies wait offscreen before starting');assert(h.qa.coverSpots().length>=4,'Cover already exists in the scenery');h.el('.cc-play').dispatch('click');h.frames(70);const running=h.qa.geometry(h.qa.enemies()[0]);assert(running.p.entry<1&&running.p.duck===0);assert(h.qa.targets().some(t=>t.id===0),'Running enemies are exposed');assert.equal(JSON.stringify(h.qa.coverSpots()),fixed,'Cover cannot travel with entering enemies');h.frames(120);const tucked=h.qa.geometry(h.qa.enemies()[0]);assert(tucked.p.duck>.9);assert(!h.qa.targets().some(t=>t.id===0),'A fully ducked enemy has no visible hit region');const c=h.qa.coverSpots()[0];shotAt(h,{x:c.x+c.w/2,y:c.y+c.h/2});assert(h.qa.enemies()[0].alive,'Shots into the fixed cover do not hit the hidden enemy');h.frames(105);const exposed=h.qa.targets().find(t=>t.id===0);assert(exposed,'Enemy emerges from the same cover');shotAt(h,exposed);assert(!h.qa.enemies()[0].alive);h.frames(20);assert.equal(JSON.stringify(h.qa.coverSpots()),fixed,'Cover remains after the enemy is defeated');results.push(scene+': fixed scenery exists before entry, runners are exposed, cover blocks shots, and scenery stays after defeat');
}
for(const scene of ['yard','reactor','docks','boat']){
 const h=harness();h.qa.selectScene(scene,false);h.el('.cc-play').dispatch('click');let steps=0;
 while(!['clear','failed'].includes(h.qa.S.phase)&&steps++<1600){
   h.frames(3);
   if(h.qa.S.phase==='moving')continue;
   const t=h.qa.targets().find(t=>h.qa.enemies()[t.id].alive);
   if(t){h.el('canvas').dispatch('pointermove',{pointerType:'mouse',clientX:t.x,clientY:t.y});h.el('canvas').dispatch('pointerdown',{pointerType:'mouse'});}
   if(h.qa.S.ammo===0){h.el('.cc-cover').dispatch('pointerdown');h.frames(50);h.el('.cc-cover').dispatch('pointerup');h.frames(16);}
 }
 assert.equal(h.qa.S.phase,'clear',scene+' must be completable: '+JSON.stringify(h.qa.S));assert.equal(h.qa.S.area,2);assert.equal(h.qa.S.hits,scene==='yard'?8:scene==='reactor'?10:12);h.frames(30);assert(h.qa.enemies().every(e=>e.deathTime===0),'Last enemy disappears after encounter clear');results.push(scene+': both areas completed with actual hit detection and automatic advance');
}
{
 const h=harness();h.el('.cc-play').dispatch('click');h.frames(10);h.el('.cc-play').dispatch('click');const time=h.qa.S.time;h.frames(300);assert.equal(h.qa.S.time,time);results.push('Pause freezes encounter timer');
}
const report={passed:true,scope:'Isolated preview logic; browser appearance checked separately',checks:results};fs.writeFileSync(path.join(__dirname,'encounter-verification.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
