const assert=require('node:assert/strict'),fs=require('node:fs'),crypto=require('node:crypto');
global.window=global;global.fengari=require('./dist/assets/fengari-web.js');require('./dist/engine.js');
const source=fs.readFileSync('dist/folder.lua','utf8'),meta=JSON.parse(fs.readFileSync('dist/source.json'));
assert.equal(crypto.createHash('sha256').update(source).digest('hex'),meta.sha256);assert.equal(meta.experimental,true);
const fresh=()=>new FolderEngine(source);
function tick(e,seconds){for(let t=0;t<seconds-1e-8;t+=.05)e.tick(Math.min(.05,seconds-t));}
function setup(e){
 for(const [field,target,down,up] of [['fold','targetFold','fold_down','fold_up'],['guide','targetGuide','guide_down','guide_up']]){
  let r=e.state();for(let i=0;r[field]!==r[target]&&i<30;i++){e.action(r[field]<r[target]?up:down);r=e.state();}
 }
 for(let i=0;i<4&&e.state().air!==e.state().targetAir;i++)e.action('air');
 e.action('proof');assert.equal(e.state().proof,true);
}
function feedFirst(e){setup(e);e.action('start_stop');while(!e.state().delivery)e.tick(.05);}
let e=fresh();e.action('proof');assert.equal(e.state().proof,false);assert.equal(e.state().spoiled,1);
const orders=new Set();for(let i=0;i<3;i++){const r=e.state();orders.add(`${r.targetFold}/${r.targetGuide}/${r.targetAir}`);assert.ok(r.stockName);assert.match(r.orderNumber,/RF-00[123]/);setup(e);e.action('reset');}
assert.equal(orders.size,3);assert.equal(e.state().orderIndex,1);
e=fresh();feedFirst(e);e.action('start_stop');e.action('catch');assert.equal(e.state().held,1);assert.equal(e.state().perfectCatches,0);
e=fresh();feedFirst(e);e.action('start_stop');tick(e,.35);e.action('catch');assert.equal(e.state().perfectCatches,1);assert.equal(e.state().combo,1);
const score=e.state().score;assert.equal(e.action('catch'),false);assert.equal(e.state().score,score);
e=fresh();feedFirst(e);e.action('start_stop');tick(e,1.3);e.action('catch');assert.equal(e.state().held,1);assert.equal(e.state().perfectCatches,0);
e=fresh();setup(e);e.action('start_stop');for(let i=0;i<400&&e.state().phase!=='jammed';i++)e.tick(.05);
assert.equal(e.state().phase,'jammed');assert.equal(e.state().jams,1);assert.equal(e.state().combo,0);
assert.equal(e.action('fold_up'),false);e.action('clear_jam');e.action('start_stop');assert.equal(e.state().phase,'paused');assert.equal(e.state().proof,false);
e.action('proof');assert.equal(e.state().proof,true);
e=fresh();setup(e);e.action('start_stop');
while(e.state().held<6){e.tick(.05);if(e.state().delivery)e.action('catch');}
assert.equal(e.action('box'),true);assert.equal(e.action('box'),false);assert.equal(e.action('catch'),false);
tick(e,.6);assert.equal(e.state().boxed,0);assert.equal(e.state().held,6);
tick(e,.65);assert.equal(e.state().boxed,6);assert.equal(e.state().boxes,1);assert.equal(e.state().held,0);
for(let order=1;order<=3;order++)for(let speed=1;speed<=3;speed++){
 e=fresh();for(let i=1;i<order;i++)e.action('reset');setup(e);
 while(e.state().speed<speed)e.action('speed_up');while(e.state().speed>speed)e.action('speed_down');
 e.action('start_stop');assert.equal(e.action('fold_down'),false);
 for(let i=0;i<2400&&e.state().phase!=='complete';i++){
  e.tick(.05);let r=e.state();
  if(r.stock===0&&r.fed<24){e.action('refill');if(r.phase==='paused')e.action('start_stop');}
  if(r.delivery&&r.oldestAge>=.3&&r.held<6&&!r.boxingRemaining)e.action('catch');
  r=e.state();if(!r.boxingRemaining&&(r.held===6||(r.fed===24&&!r.inTransit.length&&!r.delivery&&r.held)))e.action('box');
 }
 const r=e.state();assert.equal(r.phase,'complete');assert.equal(r.boxed,24);assert.equal(r.boxes,4);assert.equal(r.jams,0);
 assert.ok(r.perfectCatches>=12);assert.equal(r.rating,'GOLD RHYTHM');assert.ok(r.score>340);
 console.log(`PASS order ${order}, speed ${speed}: ${r.perfectCatches} perfect catches, ${r.score} points, ${r.time.toFixed(1)}s`);
}
e=fresh();setup(e);e.action('start_stop');while(e.state().phase!=='jammed')e.tick(.05);
e.action('clear_jam');e.action('proof');e.action('start_stop');
for(let i=0;i<1800&&e.state().phase!=='complete';i++){
 e.tick(.05);let r=e.state();if(!r.stock&&r.fed<24){e.action('refill');if(r.phase==='paused')e.action('start_stop');}
 if(r.delivery&&!r.boxingRemaining&&r.held<6)e.action('catch');r=e.state();
 if(!r.boxingRemaining&&(r.held===6||(r.fed===24&&!r.inTransit.length&&!r.delivery&&r.held)))e.action('box');
}
assert.equal(e.state().phase,'complete');assert.equal(e.state().boxed+e.state().spoiled,24);
e.action('reset');assert.equal(e.state().score,0);assert.equal(e.state().boxingRemaining,0);assert.equal(e.state().assisted,false);
e.action('assist_setup');assert.equal(e.state().assisted,true);assert.equal(e.state().proof,true);
for(let i=0;i<8;i++)e.action('rotate_view');assert.equal(e.state().view,1);
console.log('PASS hash, work orders, timing windows, anti-spam, buffer limit, packing lock, reproof, partial-box recovery, reset, assisted setup, eight views.');
