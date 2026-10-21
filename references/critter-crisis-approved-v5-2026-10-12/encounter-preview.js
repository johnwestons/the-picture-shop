(() => {
  const root = document.getElementById('cc-reference-proposal');
  const q = s => root.querySelector(s), all = s => Array.from(root.querySelectorAll(s));
  const assets = __CC_ASSET_DATA__;
  const scenes = {
    yard: {title:'NEON TRANSIT YARD',level:'01',count:4},
    reactor: {title:'REACTOR TOWER',level:'02',count:5},
    docks: {title:'FLOODLIGHT DOCKS',level:'03',count:6},
    boat: {title:'BOAT CHASE',level:'03',count:6}
  };
  const atlas = [
    [[40,8,296,268],[385,71,280,210],[712,18,320,258]],
    [[40,298,271,260],[385,324,262,239],[733,322,319,241]],
    [[36,600,295,219],[386,618,273,228],[751,595,315,226]],
    [[33,847,305,280],[382,894,306,233],[728,845,330,282]]
  ];
  const crate=[1100,937,245,174], canvas=q('canvas'), ctx=canvas.getContext('2d'), images={};
  const clamp=(x,a,b)=>Math.max(a,Math.min(b,x)), ease=t=>t*t*(3-2*t);
  const reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
  const weapons={pistol:{name:'PISTOL',capacity:12,interval:.22,reload:.65},smg:{name:'SMG',capacity:30,interval:.08,reload:.8,auto:true},shotgun:{name:'SHOTGUN',capacity:6,interval:.7,reload:1,spread:.08}};
  const rewards=[{kind:'smg',kills:3,x:.32},{kind:'shotgun',kills:6,x:.70}];
  const weaponRects={smg:{pickup:[8,98,612,383],held:[0,540,623,714]},shotgun:{pickup:[628,145,620,235],held:[625,540,629,714]}};
  const S={scene:'yard',phase:'ready',cover:false,duck:0,weapon:'pistol',ammo:12,reload:0,health:100,area:1,time:45,age:0,move:0,aimX:.5,aimY:.48,dx:0,dy:0,players:'solo',sensitivity:320,coverMode:'Hold',fireHeld:false,shotCooldown:0,hits:0,notice:'',noticeTime:0};
  const keys=new Set(); let enemies=[],targets=[],pickups=[],pickupTargets=[],earned=new Set(),fx=[],casings=[],width=736,height=460,last=0,gunFlash=0,hitFlash=0,lastAttack=-10,wheelId=null,coverId=null,fireId=null,canvasId=null,hudCache='';
  const weapon=()=>weapons[S.weapon];
  function persist(){window.openai?.setWidgetState?.({modelContent:{version:5,previewScene:S.scene,players:S.players,coverMode:S.coverMode},privateContent:{sensitivity:S.sensitivity}}).catch(()=>{});}
  function applySaved(saved){if(!saved||![3,4,5].includes(saved.modelContent?.version))return;const m=saved.modelContent;if(m.version===5&&(scenes[m.previewScene]||m.previewScene==='menu'))S.scene=m.previewScene;if(['solo','coop'].includes(m.players))S.players=m.players;if(['Hold','Tap'].includes(m.coverMode))S.coverMode=m.coverMode;if(saved.privateContent?.sensitivity)S.sensitivity=clamp(saved.privateContent.sensitivity,160,540);}
  function resize(){const b=q('.cc-stage').getBoundingClientRect();width=b.width;height=b.height;const d=Math.min(devicePixelRatio||1,2);canvas.width=Math.round(width*d);canvas.height=Math.round(height*d);ctx.setTransform(d,0,0,d,0,0);}
  function full(im,x,y,w,h){if(im?.naturalWidth)ctx.drawImage(im,x,y,w,h);}
  function background(im,x,y,w,h){if(!im?.naturalWidth)return;const r=Math.max(w/im.width,h/im.height);full(im,x+(w-im.width*r)/2,y+(h-im.height*r)/2,im.width*r,im.height*r);}
  function sprite(rect,x,y,w,h,flip=false){const im=images.atlas;if(!im?.naturalWidth)return;const r=im.width/1374;ctx.save();if(flip){ctx.translate(x+w,y);ctx.scale(-1,1);x=0;y=0;}ctx.drawImage(im,rect[0]*r,rect[1]*r,rect[2]*r,rect[3]*r,x,y,w,h);ctx.restore();}
  function stopWheel(){wheelId=null;S.dx=S.dy=0;q('.cc-knob').style.transform='translate(-50%,-50%)';}
  function releaseInputs(){keys.clear();S.fireHeld=false;S.cover=false;coverId=fireId=canvasId=null;stopWheel();}
  function spawn(){const n=(scenes[S.scene]||scenes.yard).count;enemies=Array.from({length:n},(_,i)=>({id:i,type:i%4,delay:i*.45,alive:true,shot:-1,deathTime:0}));pickupTargets=[];targets=[];S.age=0;lastAttack=-10;}
  function reset(){releaseInputs();Object.assign(S,{phase:'ready',duck:0,weapon:'pistol',ammo:12,reload:0,health:100,area:1,time:45,age:0,move:0,hits:0,shotCooldown:0,notice:'',noticeTime:0,rewardWait:0,aimX:.5,aimY:.48});fx=[];casings=[];pickups=[];earned.clear();spawn();updateHud();}
  function selectScene(scene,save=true){if(scene!=='menu'&&!scenes[scene])return;S.scene=scene;reset();q('.cc-menu').hidden=scene!=='menu';q('.cc-game-ui').hidden=scene==='menu';q('.cc-play').hidden=scene==='menu';q('.cc-stage').classList.toggle('cc-menu-open',scene==='menu');all('.cc-scenes button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.scene===scene)));canvas.setAttribute('aria-label',scene==='menu'?'Critter Crisis three-level menu':`${scenes[scene].title}: timed firefight, moving enemies, cover, automatic reload and area transition`);updateHud();requestAnimationFrame(resize);if(save)persist();}
  function play(){if(S.scene==='menu')return;if(['failed','clear'].includes(S.phase))reset();if(['active','moving','reward'].includes(S.phase)){S.resumePhase=S.phase;S.phase='paused';releaseInputs();}else if(S.phase==='paused')S.phase=S.resumePhase||'active';else S.phase='active';updateHud();}
  function setCover(on){S.cover=!!on;S.reload=0;updateHud();}
  function updateHud(){const cfg=scenes[S.scene]||scenes.yard, left=enemies.filter(e=>e.alive).length+cfg.count*(2-S.area);const event=S.phase==='moving'?'AREA CLEAR → ADVANCING':S.phase==='clear'?'ENCOUNTER CLEAR':S.phase==='failed'?(S.health===0?'OUT OF HEALTH':'TIME UP'):S.cover?(S.ammo<weapon().capacity?'IN COVER • RELOADING':S.scene==='boat'?'BEHIND THE BOW • READY':'IN COVER • READY'):'';
    const snapshot=[S.scene,S.area,S.phase,S.health,S.weapon,S.ammo,S.hits,Math.ceil(S.time),Math.ceil(S.rewardWait),left,event,S.players,S.coverMode,S.noticeTime>0,S.notice,pickups.filter(p=>p.alive).length].join('|');if(snapshot===hudCache)return;hudCache=snapshot;
    q('.cc-hud .cc-eyebrow').textContent=`LEVEL ${cfg.level}${S.players==='coop'?' • P1':''}`;q('.cc-location').textContent=cfg.title;q('.cc-health').textContent=S.health;q('.cc-weapon').textContent=weapon().auto?'SMG AUTO':weapon().name;q('.cc-ammo').textContent=`${S.ammo} / ${weapon().capacity}`;q('.cc-wave-label').textContent=`AREA ${S.area} / 2`;q('.cc-enemies').textContent=`${left} enemies left`;q('.cc-time').textContent=S.phase==='reward'?`${Math.ceil(S.rewardWait)}s reward`:`${Math.ceil(S.time)}s`;
    const next=rewards.find(r=>!earned.has(r.kind)),drop=pickups.find(p=>p.alive);q('.cc-reward').textContent=drop?`${weapons[drop.kind].name} EARNED · SHOOT TO CLAIM`:next?`NEXT DROP · ${weapons[next.kind].name} · ${S.hits} / ${next.kills} DEFEATS`:'WEAPON REWARDS CLAIMED';
    q('.cc-cover').setAttribute('aria-pressed',String(S.cover));q('.cc-cover span').textContent=S.cover&&S.coverMode==='Tap'?'STAND':'COVER';q('.cc-cover small').textContent=`${S.coverMode.toUpperCase()} + RELOAD`;q('.cc-cover-status').textContent=event;q('.cc-cover-status').hidden=!event;
    q('.cc-fire').disabled=S.cover||S.ammo===0||['moving','failed','clear','paused'].includes(S.phase);q('.cc-play').textContent=S.phase==='paused'?'RESUME':['active','moving','reward'].includes(S.phase)?'PAUSE':S.phase==='ready'?'START ENCOUNTER':'REPLAY ENCOUNTER';
    q('.cc-caption').textContent=S.scene==='menu'?'Three levels · Direct boat chase entry · 2P layout preview':S.phase==='clear'?'Both areas cleared · Choose another level or replay':S.phase==='failed'?'Try again · Duck when enemies flash red':S.phase==='reward'?'Area clear · Shoot your earned gun before advancing':S.noticeTime>0?S.notice:weapon().auto?`Hold FIRE for full auto · ${S.coverMode} COVER to reload`:`Defeat enemies to earn weapon drops · ${S.coverMode} COVER to reload`;
    q('.cc-player-status').textContent=S.players==='coop'?'2P layout preview · One device per player · Wi-Fi / hotspot':'One player';all('[data-players]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.players===S.players)));
  }
  function posture(e){const land=S.scene!=='boat',travel=land?2.2:1.2,age=S.age-e.delay,c=((Math.max(0,age-travel)+e.id*.8)%6.5),cycle=Math.floor((Math.max(0,age-travel)+e.id*.8)/6.5);if(S.phase==='ready')return {entry:land?0:1,duck:land?0:e.id%2?.15:.65,warn:0,cycle:0,c:0,hidden:land};const entry=clamp(age/travel,0,1);let duck=c<1?1:c<1.4?1-(c-1)/.4:c<4.6?0:clamp((c-4.6)/.3,0,1);if(land&&entry<1)duck=0;return {entry,duck,warn:entry===1&&c>3.3&&c<4.45?(c-3.3)/1.15:0,cycle,c,hidden:age<0};}
  function layout(){if(S.scene==='boat')return [[.15,.53],[.39,.51],[.63,.51],[.85,.53],[.31,.69],[.69,.69]];const cfg=scenes[S.scene]||scenes.yard;return cfg.count===4?[[.19,.72],[.40,.68],[.64,.79],[.83,.70]]:cfg.count===5?[[.15,.71],[.39,.66],[.62,.70],[.84,.69],[.50,.80]]:[[.15,.69],[.39,.66],[.63,.66],[.85,.69],[.31,.80],[.69,.80]];}
  function station(id){const pos=layout()[id],near=pos[1]>(S.scene==='boat'?.63:.75),w=clamp(width*(near?.17:.14),46,126);return {x:(pos[0]+(S.area===2?(id%2?1:-1)*.015:0))*width,y:pos[1]*height+S.duck*height*.09,w,h:w*.94};}
  function coverGeometry(id){const s=station(id);return {id,x:s.x-s.w*.58,y:s.y-s.h*.44,w:s.w*1.16,h:s.h*.53,depth:s.y+s.h*.09};}
  function coverSpots(){return S.scene==='boat'||S.scene==='menu'?[]:layout().map((_,i)=>coverGeometry(i));}
  function geometry(e){const p=posture(e),s=station(e.id);let {x,y,w,h}=s;if(S.scene==='boat'){if(!reduced)x+=(1-ease(p.entry))*(e.id%2===0?-1:1)*width*.28;if(!reduced&&S.phase!=='ready'){x+=Math.sin(S.age*.8+e.id)*width*.03;y+=Math.sin(S.age*1.4+e.id)*3;}}else{const from=e.id%2===0?-w:width+w;x=from+(s.x-from)*(reduced?1:p.entry);if(p.entry===1)x+=(e.id%2?1:-1)*w*.10*(1-p.duck);}return {e,p,x,y,w,h};}
  function drawFixedCover(c){ctx.fillStyle='#02101888';ctx.beginPath();ctx.ellipse(c.x+c.w/2,c.y+c.h,c.w*.58,c.h*.13,0,0,Math.PI*2);ctx.fill();sprite(crate,c.x,c.y,c.w,c.h);}
  function clipTargetsToCover(){const covers=coverSpots();targets=targets.flatMap(t=>{let parts=[{l:t.x-t.w/2,r:t.x+t.w/2,top:t.y-t.h/2,b:t.y+t.h/2}];for(const c of covers){if(c.depth<t.depth)continue;parts=parts.flatMap(a=>{const l=Math.max(a.l,c.x),r=Math.min(a.r,c.x+c.w),top=Math.max(a.top,c.y),b=Math.min(a.b,c.y+c.h);if(l>=r||top>=b)return [a];return [{l:a.l,r:a.r,top:a.top,b:top},{l:a.l,r:a.r,top:b,b:a.b},{l:a.l,r:l,top,b},{l:r,r:a.r,top,b}].filter(v=>v.r-v.l>3&&v.b-v.top>3);});}return parts.map(a=>({...t,x:(a.l+a.r)/2,y:(a.top+a.b)/2,w:a.r-a.l,h:a.b-a.top}));});}
  function enemyFire(e,p){if(!e.alive||p.entry<1||p.c<4.4||p.c>=4.6||e.shot===p.cycle)return;e.shot=p.cycle;if(S.age-lastAttack<.48)return;lastAttack=S.age;const g=geometry(e);fx.push({kind:'shot',x:g.x,y:g.y-g.h*.62,life:.22});if(S.cover&&S.duck>.6){fx.push({kind:'spark',x:width*(.28+(e.id%3)*.2),y:height*.69,life:.28});}else{S.health=Math.max(0,S.health-10);hitFlash=.14;if(S.health===0){S.phase='failed';releaseInputs();}}}
  function update(dt){gunFlash=Math.max(0,gunFlash-dt);hitFlash=Math.max(0,hitFlash-dt);S.shotCooldown=Math.max(-.05,S.shotCooldown-dt);fx=fx.filter(f=>(f.life-=dt)>0);for(const e of enemies)if(!e.alive)e.deathTime=Math.max(0,e.deathTime-dt);S.noticeTime=Math.max(0,S.noticeTime-dt);if(S.phase!=='paused'){for(const p of pickups)p.age+=dt;casings=casings.filter(c=>(c.age+=dt)<.55);}S.duck=reduced?(S.cover?1:0):S.duck+((S.cover?1:0)-S.duck)*Math.min(1,dt*15);
    if(S.scene==='menu')return;const dx=S.dx+(keys.has('ArrowRight')?1:0)-(keys.has('ArrowLeft')?1:0),dy=S.dy+(keys.has('ArrowDown')?1:0)-(keys.has('ArrowUp')?1:0);S.aimX=clamp(S.aimX+dx*S.sensitivity*dt/736,.03,.97);S.aimY=clamp(S.aimY+dy*S.sensitivity*dt/460,.16,.82);
    if(S.cover&&S.ammo<weapon().capacity&&!['paused','moving','clear','failed'].includes(S.phase)){S.reload+=dt;if(S.reload>=weapon().reload){S.ammo=weapon().capacity;S.reload=0;}}if(S.fireHeld&&weapon().auto)shoot();
    if(S.phase==='reward'){S.rewardWait-=dt;if(S.rewardWait<=0||!pickups.some(p=>p.alive)){S.phase=S.area===1?'moving':'clear';S.move=0;releaseInputs();}}
    if(S.phase==='moving'){S.move+=dt;if(S.move>=1.5){S.area=2;S.time=45;S.ammo=weapon().capacity;S.phase='active';S.move=0;spawn();}}
    else if(S.phase==='active'){S.age+=dt;S.time=Math.max(0,S.time-dt);for(const e of enemies)enemyFire(e,posture(e));if(S.time===0){S.phase='failed';releaseInputs();}}
    updateHud();
  }
  function polygon(points){ctx.beginPath();points.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.closePath();}
  function drawBoatEnemy(g){const {e,p,x,y,w,h}=g,bx=x-w*.93,by=y-h*.55,bw=w*1.9,bh=bw*2/3;
    full(images.boat,bx,by,bw,bh);
    const headY=y-h*.9+p.duck*h*.96,limit=by+bh*.39;
    // The critter sinks into the cockpit; the front hull occludes the body.
    ctx.save();ctx.beginPath();ctx.rect(x-w,by-h,w*2,limit-by+h);ctx.clip();sprite(atlas[e.type][0],x-w*.39,headY,w*.78,h*.95);ctx.restore();
    ctx.save();polygon([[.18,.39],[.29,.38],[.36,.41],[.39,.28],[.43,.31],[.45,.39],[.52,.41],[.53,.34],[.64,.32],[.68,.39],[.74,.44],[.79,.49],[.87,.66],[.96,1],[0,1]].map(([a,b])=>[bx+a*bw,by+b*bh]));ctx.clip();full(images.boat,bx,by,bw,bh);ctx.restore();
    const exposedHeight=Math.min(h*.66,limit-headY);
    if(e.alive&&p.duck<.6&&exposedHeight>h*.22)targets.push({id:e.id,x,y:headY+exposedHeight/2,w:w*.68,h:exposedHeight});
    drawWarning(p,x,headY,w,h);
  }
  function drawWarning(p,x,headY,w,h){if(p.warn>0){ctx.lineWidth=2.5;ctx.strokeStyle=p.warn>.55?'#ff654d':'#ffd75c';ctx.beginPath();ctx.arc(x,headY+h*.25,w*.5,-Math.PI/2,-Math.PI/2+Math.PI*2*p.warn);ctx.stroke();ctx.fillStyle=ctx.strokeStyle;ctx.font='bold 13px Arial';ctx.textAlign='center';ctx.fillText('!',x,headY-5);}}
  function drawEnemy(g){const {e,p,x,y,w,h}=g;if(p.hidden)return;if(S.scene==='boat'){drawBoatEnemy(g);return;}
    ctx.fillStyle='#02101866';ctx.beginPath();ctx.ellipse(x,y+w*.08,w*.64,w*.11,0,0,Math.PI*2);ctx.fill();
    const isRunning=p.entry<1;
    const headY=y-h+p.duck*h*.68;
    ctx.save();ctx.beginPath();ctx.rect(x-w,y-h*1.5,w*2,h*1.58);ctx.clip();sprite(atlas[e.type][isRunning?2:0],x-w/2,headY,w,h,isRunning&&e.id%2===1);ctx.restore();
    if(e.alive)targets.push({id:e.id,x,y:(headY+y)/2,w:w*.78,h:y-headY,depth:y});
    drawWarning(p,x,headY,w,h);
  }
  function drawBow(cam,bob){const im=images.boatScene;if(!im?.naturalWidth)return;
    const zoom=reduced?1:1+cam*.07,r=Math.max(width*zoom/im.width,(height*zoom+12)/im.height)*(1+S.duck*.8),bw=im.width*r,bh=im.height*r;
    const x=(width-bw)/2-cam*width*.014,y=height-bh+12+bob;
    // Reuse the actual bow from the scene, with a camera dip behind its front rim.
    ctx.save();polygon([[.035,1],[.30,.82],[.329,.792],[.342,.751],[.455,.724],[.464,.746],[.535,.725],[.586,.727],[.65,.756],[.688,.779],[.703,.824],[.968,1]].map(([a,b])=>[x+a*bw,y+b*bh]));ctx.clip();full(im,x,y,bw,bh);ctx.restore();
  }
  function weaponSprite(kind,view,x,y,w,h){const im=images.weapons;if(!im?.naturalWidth)return;const r=im.width/1254,rect=weaponRects[kind][view];ctx.drawImage(im,rect[0]*r,rect[1]*r,rect[2]*r,rect[3]*r,x,y,w,h);}
  function awardDrop(hit){for(const reward of rewards){if(S.hits<reward.kills||earned.has(reward.kind))continue;earned.add(reward.kind);pickups.push({...reward,alive:true,age:0,fromX:clamp(hit.x/width,.12,.88),fromY:clamp(hit.y/height,.3,.7)});S.notice=`${reward.kills} DEFEATS · ${weapons[reward.kind].name} DROPPED · Shoot to claim`;S.noticeTime=4;}}
  function pickupGeometry(p){const t=reduced?1:ease(clamp(p.age/.7,0,1)),destY=Math.max(168,height*.37),w=clamp(width*.16,86,126),rect=weaponRects[p.kind].pickup,h=w*rect[3]/rect[2];return {x:width*(p.fromX+(p.x-p.fromX)*t),y:p.fromY*height+(destY-p.fromY*height)*t-(reduced?0:Math.sin(t*Math.PI)*38)+S.duck*height*.06+(reduced?0:Math.sin(p.age*2)*3),w,h,t};}
  function drawPickups(){pickupTargets=[];if(['moving','clear','failed'].includes(S.phase))return;
    for(const p of pickups){if(!p.alive)continue;const {x,y,w,h,t}=pickupGeometry(p);
      ctx.save();ctx.globalAlpha=1-S.duck*.7;const halo=ctx.createRadialGradient(x,y,3,x,y,w*.67);halo.addColorStop(0,'#f5c95577');halo.addColorStop(.6,'#efaf282c');halo.addColorStop(1,'#e9a32700');ctx.fillStyle=halo;ctx.fillRect(x-w*.7,y-w*.7,w*1.4,w*1.4);ctx.strokeStyle='#ffe8a0aa';ctx.lineWidth=1;ctx.beginPath();ctx.ellipse(x,y+h*.5+5,w*.46,5,0,0,Math.PI*2);ctx.stroke();ctx.shadowColor='#ffdc80';ctx.shadowBlur=7;weaponSprite(p.kind,'pickup',x-w/2,y-h/2,w,h);ctx.shadowBlur=0;ctx.fillStyle='#fff0bc';ctx.font='bold 11px Arial';ctx.textAlign='center';ctx.strokeStyle='#08131d';ctx.lineWidth=4;const label=`${weapons[p.kind].name} · SHOOT`;ctx.strokeText(label,x,y+h/2+23);ctx.fillText(label,x,y+h/2+23);ctx.restore();if(t===1)pickupTargets.push({pickup:p,x,y,w:w+10,h:Math.max(44,h+10)});
    }
  }
  function drawPlayerGun(){const x=width*.52;if(S.weapon==='pistol'){const gw=clamp(width*.26,95,240),y=height-gw*.75+S.duck*gw*1.2+(gunFlash>0?5:0);full(images.gun,x-gw/2,y,gw,gw);return {x,muzzleY:height-gw*.67};}
    const gh=clamp(width*.32,135,255),rect=weaponRects[S.weapon].held,gw=gh*rect[2]/rect[3],age=weapon().interval-Math.max(0,S.shotCooldown),kick=reduced?0:S.weapon==='shotgun'?Math.sin(clamp(age/.3,0,1)*Math.PI)*17:gunFlash>0?6:0;
    const muzzle=S.weapon==='shotgun'?.30:.43,y=height-gh*.81+S.duck*gh*1.15+kick,left=x-gw*muzzle;weaponSprite(S.weapon,'held',left,y,gw,gh);return {x,muzzleY:y+gh*.055};
  }
  function draw(){ctx.clearRect(0,0,width,height);const key=S.scene==='menu'?'yard':S.scene, cam=S.phase==='moving'?ease(clamp(S.move/1.5,0,1)):S.area===2?1:0;const zoom=reduced?1:1+cam*.07,bob=key==='boat'&&!reduced&&S.phase==='active'?Math.sin(S.age*1.3)*2:0;background(images[key==='boat'?'boatScene':key],-width*(zoom-1)/2-cam*width*.014,-height*(zoom-1)/2+S.duck*height*.055+bob,width*zoom,height*zoom+12);ctx.fillStyle='#07131b18';ctx.fillRect(0,0,width,height);if(S.scene==='menu')return;
    targets=[];const nodes=coverSpots().map(c=>({depth:c.depth,cover:c}));for(const e of enemies){const g=geometry(e);nodes.push({depth:g.y,g});}nodes.sort((a,b)=>a.depth-b.depth);for(const node of nodes){if(node.cover){drawFixedCover(node.cover);continue;}const g=node.g,e=g.e;if(e.alive)drawEnemy(g);else if(!reduced&&e.deathTime>0){ctx.save();ctx.globalAlpha=e.deathTime/.22;g.y+=20*(1-e.deathTime/.22);drawEnemy(g);ctx.restore();}}if(S.scene!=='boat')clipTargetsToCover();
    const shade=ctx.createLinearGradient(0,height*.7,0,height);shade.addColorStop(0,'#07131b00');shade.addColorStop(1,'#07131bbf');ctx.fillStyle=shade;ctx.fillRect(0,height*.7,width,height*.3);
    if(S.scene==='boat')drawBow(cam,bob);
    const gun=drawPlayerGun();
    if(S.scene!=='boat'){const cw=width*.31,ch=Math.max(cw*.71,height*.46),ct=height*.94-S.duck*height*.34;for(let i=0;i<4;i++)sprite(crate,-width*.02+i*cw*.85,ct+(i%2?5:0),cw,ch);}
    drawPickups();
    for(const f of fx){ctx.save();ctx.globalAlpha=Math.min(1,f.life*6);ctx.strokeStyle=f.kind==='hit'?'#b6ffff':f.kind==='shot'?'#ff8b5b':'#ffdb83';ctx.fillStyle=ctx.strokeStyle;ctx.lineWidth=2;const n=f.kind==='shot'?14:9;ctx.beginPath();for(let i=0;i<8;i++){const a=i*Math.PI/4;ctx.moveTo(f.x+Math.cos(a)*3,f.y+Math.sin(a)*3);ctx.lineTo(f.x+Math.cos(a)*n,f.y+Math.sin(a)*n);}ctx.stroke();ctx.restore();}
    const ax=S.aimX*width,ay=S.aimY*height;ctx.save();ctx.globalAlpha=1-S.duck*.75;ctx.strokeStyle=gunFlash>0?'#fff2a6':'#8ef6ff';ctx.lineWidth=2;ctx.shadowColor='#00121b';ctx.shadowBlur=3;ctx.beginPath();ctx.arc(ax,ay,S.weapon==='shotgun'?width*weapon().spread:12,0,Math.PI*2);ctx.stroke();ctx.beginPath();for(const [a,b,c,d]of [[-20,0,-7,0],[7,0,20,0],[0,-20,0,-7],[0,7,0,20]]){ctx.moveTo(ax+a,ay+b);ctx.lineTo(ax+c,ay+d);}ctx.stroke();ctx.fillStyle='#e9ffff';ctx.fillRect(ax-1,ay-1,2,2);ctx.restore();
    if(gunFlash>0&&!S.cover){const radius=S.weapon==='shotgun'?23:15;ctx.fillStyle='#ffc443bb';polygon(Array.from({length:12},(_,i)=>{const a=i*Math.PI/6,r=i%2?radius*.35:radius;return [gun.x+Math.cos(a)*r,gun.muzzleY+Math.sin(a)*r];}));ctx.fill();ctx.fillStyle='#fff8df';ctx.beginPath();ctx.arc(gun.x,gun.muzzleY,5,0,Math.PI*2);ctx.fill();}
    if(!reduced)for(const c of casings){ctx.save();ctx.globalAlpha=1-c.age/.55;ctx.translate(width*.59+c.age*150,height*.80-c.age*150+c.age*c.age*220);ctx.rotate(c.age*16);ctx.fillStyle=c.shell?'#bb3925':'#d9ad5e';ctx.fillRect(-4,-2,c.shell?11:7,4);ctx.fillStyle='#fae0a4';ctx.fillRect(-4,-2,2,4);ctx.restore();}
    if(hitFlash>0&&!reduced){ctx.fillStyle='#ff382b18';ctx.fillRect(0,0,width,height);}if(S.phase==='moving'){ctx.fillStyle=`rgba(5,18,28,${Math.sin(S.move/1.5*Math.PI)*.28})`;ctx.fillRect(0,0,width,height);}
    root.dataset.aimX=S.aimX.toFixed(4);root.dataset.aimY=S.aimY.toFixed(4);root.dataset.cover=S.duck.toFixed(3);root.dataset.phase=S.phase;root.dataset.area=S.area;root.dataset.weapon=S.weapon;root.dataset.targets=targets.length;root.dataset.loaded=Object.values(images).filter(im=>im.naturalWidth).length;
  }
  function shoot(){if(S.scene==='menu'||S.cover||S.duck>.35||S.ammo===0||S.shotCooldown>0||['paused','moving','failed','clear'].includes(S.phase))return;if(S.phase==='ready')S.phase='active';const fired=weapon();S.ammo--;S.shotCooldown=fired.interval+(fired.auto?Math.min(0,S.shotCooldown):0);gunFlash=fired.auto?.035:.07;if(S.weapon!=='pistol')casings.push({age:0,shell:S.weapon==='shotgun'});const x=S.aimX*width,y=S.aimY*height;
    const pickup=pickupTargets.find(t=>t.pickup.alive&&Math.abs(x-t.x)<=t.w/2&&Math.abs(y-t.y)<=t.h/2);
    if(pickup){pickup.pickup.alive=false;S.weapon=pickup.pickup.kind;S.ammo=weapon().capacity;S.reload=0;S.notice=`${weapon().name} ACQUIRED · ${S.weapon==='smg'?'FULL AUTO · Hold FIRE':'Pump action · 6 shells'}`;S.noticeTime=3;fx.push({kind:'hit',x,y,life:.35});updateHud();return;}
    const seen=new Set(),hits=[...targets].reverse().filter(t=>{const hit=enemies[t.id].alive&&!seen.has(t.id)&&(fired.spread?Math.hypot(Math.max(0,Math.abs(x-t.x)-t.w/2),Math.max(0,Math.abs(y-t.y)-t.h/2))<=width*fired.spread:Math.abs(x-t.x)<t.w*.5&&Math.abs(y-t.y)<t.h*.5);if(hit)seen.add(t.id);return hit;});
    if(!fired.spread)hits.splice(1);fx.push({kind:hits.length?'hit':'spark',x,y,life:.2});for(const hit of hits){const e=enemies[hit.id];e.alive=false;e.deathTime=.22;S.hits++;awardDrop(hit);fx.push({kind:'hit',x:hit.x,y:hit.y,life:.22});}
    if(hits.length&&enemies.every(e=>!e.alive)){releaseInputs();if(pickups.some(p=>p.alive)){S.phase='reward';S.rewardWait=8;}else if(S.area===1){S.phase='moving';S.move=0;}else S.phase='clear';}updateHud();
  }
  const wheel=q('.cc-wheel'),knob=q('.cc-knob');
  function wheelMove(e){if(e.pointerId!==wheelId)return;const b=wheel.getBoundingClientRect(),r=b.width*.32;let x=e.clientX-b.left-b.width/2,y=e.clientY-b.top-b.height/2;const d=Math.hypot(x,y);if(d>r){x*=r/d;y*=r/d;}S.dx=Math.abs(x/r)<.08?0:x/r;S.dy=Math.abs(y/r)<.08?0:y/r;knob.style.transform=`translate(calc(-50% + ${x}px),calc(-50% + ${y}px))`;}
  wheel.addEventListener('pointerdown',e=>{if(wheelId!==null)return;e.preventDefault();wheelId=e.pointerId;wheel.setPointerCapture(wheelId);wheelMove(e);});wheel.addEventListener('pointermove',wheelMove);['pointerup','pointercancel','lostpointercapture'].forEach(type=>wheel.addEventListener(type,e=>{if(e.pointerId===wheelId)stopWheel();}));
  const cover=q('.cc-cover'),fire=q('.cc-fire');
  function syncFire(){S.fireHeld=fireId!==null||canvasId!==null||keys.has('KeyF');}
  function beginFire(){syncFire();S.shotCooldown=Math.max(0,S.shotCooldown);shoot();}
  cover.addEventListener('pointerdown',e=>{if(S.coverMode!=='Hold')return;e.preventDefault();coverId=e.pointerId;cover.setPointerCapture(coverId);setCover(true);});['pointerup','pointercancel','lostpointercapture'].forEach(type=>cover.addEventListener(type,e=>{if(e.pointerId===coverId){coverId=null;setCover(false);}}));cover.addEventListener('click',e=>{if(S.coverMode==='Tap'||e.detail===0)setCover(!S.cover);});
  fire.addEventListener('pointerdown',e=>{e.preventDefault();fireId=e.pointerId;fire.setPointerCapture(fireId);beginFire();});['pointerup','pointercancel','lostpointercapture'].forEach(type=>fire.addEventListener(type,e=>{if(e.pointerId===fireId){fireId=null;syncFire();}}));fire.addEventListener('click',e=>{if(e.detail===0)shoot();});
  function aimMouse(e){if(e.pointerType!=='mouse'||S.scene==='menu'||!Number.isFinite(e.clientX))return;const b=canvas.getBoundingClientRect();S.aimX=clamp((e.clientX-b.left)/b.width,.03,.97);S.aimY=clamp((e.clientY-b.top)/b.height,.16,.82);}
  canvas.addEventListener('pointermove',aimMouse);canvas.addEventListener('pointerdown',e=>{if(e.pointerType!=='mouse'||e.button>0)return;e.preventDefault();aimMouse(e);canvasId=e.pointerId;canvas.setPointerCapture(canvasId);beginFire();});['pointerup','pointercancel','lostpointercapture'].forEach(type=>canvas.addEventListener(type,e=>{if(e.pointerId===canvasId){canvasId=null;syncFire();}}));
  q('.cc-play').addEventListener('click',play);all('[data-scene]').forEach(b=>b.addEventListener('click',()=>selectScene(b.dataset.scene)));all('[data-players]').forEach(b=>b.addEventListener('click',()=>{S.players=b.dataset.players;updateHud();persist();}));
  root.addEventListener('keydown',e=>{if(['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key)){e.preventDefault();keys.add(e.key);}if(e.code==='KeyF'){e.preventDefault();if(!keys.has('KeyF')){keys.add('KeyF');beginFire();}}if(e.code==='Space'||e.code==='KeyR'){e.preventDefault();setCover(true);}});root.addEventListener('keyup',e=>{keys.delete(e.key);if(e.code==='KeyF'){keys.delete('KeyF');syncFire();}if(e.code==='Space'||e.code==='KeyR'){e.preventDefault();setCover(false);}});
  function suspend(){releaseInputs();if(['active','moving','reward'].includes(S.phase)){S.resumePhase=S.phase;S.phase='paused';}updateHud();}window.addEventListener('blur',suspend);document.addEventListener('visibilitychange',()=>{if(document.hidden)suspend();});
  function frame(stamp){const dt=Math.min(.05,(stamp-last)/1000||0);last=stamp;update(dt);draw();requestAnimationFrame(frame);}
  for(const [name,src]of Object.entries(assets)){const im=new Image();images[name]=im;im.src=src;}all('[data-bg]').forEach(el=>el.style.backgroundImage=`url(${assets[el.dataset.bg]})`);
  applySaved(window.openai?.widgetState);selectScene(S.scene,false);new ResizeObserver(resize).observe(q('.cc-stage'));resize();requestAnimationFrame(frame);
  window.addEventListener('openai:set_globals',e=>{const saved=e.detail?.globals?.widgetState;if(![3,4,5].includes(saved?.modelContent?.version))return;const previous=S.scene;applySaved(saved);if(previous!==S.scene)selectScene(S.scene,false);else updateHud();});
  if(globalThis.Tweak){const tweak=new Tweak({container:q('.cc-product'),onChange:()=>{releaseInputs();updateHud();persist();}});tweak.addSlider(S,'sensitivity',{label:'Aim speed',min:160,max:540,step:20});tweak.addSelect(S,'coverMode',{label:'Cover control',options:['Hold','Tap']});}
})();
