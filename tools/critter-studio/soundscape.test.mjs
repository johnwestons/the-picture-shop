import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';import os from 'node:os';import path from 'node:path';import http from 'node:http';
import {createSoundscape,inspectPCM,generatedFactory} from './soundscape.mjs';
import {encodePCM,processSound} from './soundscape-dsp.mjs';
test('soundscape keeps stereo, supports music length, rejects malformed PCM',()=>{
 const left=new Float32Array(48000).fill(.2),right=new Float32Array(48000).fill(-.3);
 const wav=Buffer.from(encodePCM([left,right],48000)),info=inspectPCM(wav);assert.equal(info.channels,2);assert.equal(info.duration,1);
 const out=processSound([left,right],48000,{start:0,end:1,pitch:0,gain:0,bits:8,crush:0,fade:0,normalize:false,clean:false,mono:false});assert.deepEqual(out.channels[0],left);assert.deepEqual(out.channels[1],right);
 assert.throws(()=>inspectPCM(wav.subarray(0,100)));assert.throws(()=>processSound([left],48000,{start:1,end:.1}));
 const long=Buffer.from(encodePCM([new Float32Array(24000*121)],24000));assert.equal(inspectPCM(long).duration,121);
});
test('imports, selects, publishes only chosen files, and restores factory audio',async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'soundscape-test-'));fs.mkdirSync(path.join(root,'src'));
 fs.writeFileSync(path.join(root,'src/sound.lua'),'door={path="assets/audio/sfx/door.wav",volume=.7}');fs.writeFileSync(path.join(root,'src/jukebox.lua'),'');
 const handler=createSoundscape(root),token='test';let origin;
 const server=http.createServer((req,res)=>handler(req,res,new URL(req.url,origin),token,origin));await new Promise(r=>server.listen(0,'127.0.0.1',r));origin=`http://127.0.0.1:${server.address().port}`;
 const headers={Origin:origin,'X-Studio-Token':token};
 const post=async(endpoint,data)=>{const r=await fetch(origin+'/sc/'+endpoint,{method:'POST',headers,body:JSON.stringify(data)});return {status:r.status,data:await r.json()};};
 try{
  assert.equal((await fetch(origin+'/sc/apply',{method:'POST',body:'{}'})).status,403);
  for(const [id,duration]of [['shop-phone_ring_loop',2],['shop-phone_ringback_loop',1],['commute-horn',.5]]){
   const response=await fetch(origin+'/sc/factory/'+id);assert.equal(response.status,200);
   const wav=Buffer.from(await response.arrayBuffer());assert.equal(inspectPCM(wav).duration,duration);
   assert.deepEqual(wav,generatedFactory(id));assert.ok(wav.subarray(44).some(v=>v!==0));
  }
  assert.equal((await fetch(origin+'/sc/factory/not-a-slot')).status,400);
  assert.throws(()=>generatedFactory('bad'));
  const audio=Buffer.from(encodePCM([new Float32Array(4800).fill(.2),new Float32Array(4800).fill(-.2)],48000));
  const upload=async()=>{const r=await fetch(origin+'/sc/upload?slot=shop-door&label=Test',{method:'POST',headers,body:audio});return {status:r.status,data:await r.json()};};
  const take=await upload();assert.equal(take.status,201);assert.equal((await upload()).status,200);
  assert.equal((await post('slot',{slot:'shop-door',selected:take.data.id,gain:.6,muted:false})).status,200);
  assert.equal((await post('mix',{master:.8,sfx:.7,ambience:1,music:.3})).status,200);
  const applied=await post('apply',{});assert.equal(applied.status,200);assert.equal(applied.data.files.length,1);assert.equal(applied.data.bytes,audio.length);
  assert.deepEqual(fs.readFileSync(path.join(root,applied.data.files[0])),audio);
  const lua=fs.readFileSync(path.join(root,'assets/audio/custom/manifest.lua'),'utf8');assert.match(lua,/master=0.8/);assert.match(lua,/gain=0.6/);
  assert.equal((await post('delete',{slot:'shop-door',id:take.data.id})).status,400);
  assert.equal((await post('slot',{slot:'shop-door',selected:null,gain:1,muted:false})).status,200);
  assert.equal((await post('apply',{})).data.files.length,0);
  assert.equal((await post('delete',{slot:'shop-door',id:take.data.id})).status,200);
  assert.equal((await post('slot',{slot:'shop-door',selected:'../../bad',gain:1})).status,400);
 }finally{await new Promise(r=>server.close(r));fs.rmSync(root,{recursive:true,force:true});}
});
