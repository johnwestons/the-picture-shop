import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {createStudio,validateWav} from './server.mjs';
import {processAudio,encodeWav,decodeWav} from './effects.mjs';
import {applyVoiceBatch} from './batch.mjs';
function wav(){const b=Buffer.alloc(44+9600);b.write('RIFF');b.writeUInt32LE(b.length-8,4);b.write('WAVEfmt ',8);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(48000,24);b.writeUInt32LE(96000,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(9600,40);return b;}
test('rejects compressed, stereo, wrong-rate, and truncated WAV',()=>{assert.equal(validateWav(wav()),.1);for(const [offset,value] of [[20,3],[22,2],[24,44100]]){const b=wav();b.writeUInt16LE(value,offset);assert.throws(()=>validateWav(b));}assert.throws(()=>validateWav(wav().subarray(0,50)));});
test('Grandpa can record and choose an independent greeting',async()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'grandpa-voice-test-')),server=createStudio(dir);
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin=`http://127.0.0.1:${server.address().port}`;
 try{
  const initial=await(await fetch(origin+'/api/library')).json();
  assert.equal(initial.characters.find(c=>c.id==='grandpa')?.name,'Grandpa');
  const headers={Origin:origin,'X-Studio-Token':initial.token};
  const saved=await fetch(origin+'/api/takes?character=grandpa&emotion=greeting',{method:'POST',headers,body:wav()});
  assert.equal(saved.status,201);
  const take=(await(await fetch(origin+'/api/library')).json()).takes.find(t=>t.character==='grandpa');
  assert.equal(take.emotion,'greeting');
  assert.equal((await fetch(origin+'/api/select',{method:'POST',headers,body:JSON.stringify({character:'grandpa',emotion:'greeting',name:take.name})})).status,200);
  const chosen=await(await fetch(origin+'/api/library')).json();
  assert.equal(chosen.selected['grandpa/greeting'],take.name);
  assert.equal(chosen.selected['cat-worker/greeting'],undefined);
 }finally{await new Promise(r=>server.close(r));fs.rmSync(dir,{recursive:true,force:true});}
});
test('saves distinct takes, reloads from disk, serves audio, rejects unsafe writes',async()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'critter-studio-test-')),server=createStudio(dir);
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin=`http://127.0.0.1:${server.address().port}`;
 try{
  const data=await(await fetch(origin+'/api/library')).json();assert.ok(data.characters.some(c=>c.id==='cat-worker'));
  const headers={Origin:origin,'X-Studio-Token':data.token};const url=origin+'/api/takes?character=cat-worker&emotion=happy';
  assert.equal((await fetch(url,{method:'POST',body:wav()})).status,403);
  assert.equal((await fetch(url,{method:'POST',headers:{...headers,Origin:'https://example.com'},body:wav()})).status,403);
  assert.equal((await fetch(origin+'/api/takes?character=../bad&emotion=happy',{method:'POST',headers,body:wav()})).status,400);
  assert.equal((await fetch(url,{method:'POST',headers,body:Buffer.from('bad')})).status,400);
  for(let i=0;i<2;i++)assert.equal((await fetch(url,{method:'POST',headers,body:wav()})).status,201);
  const saved=await(await fetch(origin+'/api/library')).json();assert.equal(saved.takes.length,2);assert.notEqual(saved.takes[0].name,saved.takes[1].name);
  const audio=await fetch(origin+saved.takes[0].url);assert.equal(audio.headers.get('content-type'),'audio/wav');assert.deepEqual(Buffer.from(await audio.arrayBuffer()),wav());
  const version={character:'cat-worker',emotion:'happy',source:saved.takes[0].name,label:'Soft 8-bit',settings:{crush:45,rate:24000}};
  const versionRequest=()=>fetch(origin+'/api/versions',{method:'POST',headers,body:JSON.stringify(version)});
  const edited=await versionRequest();assert.equal(edited.status,201);const result=await edited.json();
  assert.equal((await versionRequest()).status,200);
  const updated=await(await fetch(origin+'/api/library')).json();assert.equal(updated.takes.length,3);
  const edit=updated.takes.find(t=>t.name===result.name);assert.equal(edit.label,'Soft 8-bit');assert.equal(edit.kind,'edited');assert.ok(edit.bytes<saved.takes[0].bytes);
  const output=Buffer.from(await(await fetch(origin+edit.url)).arrayBuffer());assert.equal(output.readUInt32LE(24),24000);assert.equal(validateWav(output,[24000]),.1);
  assert.deepEqual(fs.readFileSync(path.join(dir,'cat-worker','happy',version.source)),wav());
  version.source='../outside.wav';assert.equal((await versionRequest()).status,400);
  const post=(endpoint,body)=>fetch(origin+endpoint,{method:'POST',headers,body:JSON.stringify(body)});
  assert.equal((await post('/api/preset',{character:'cat-worker',settings:{pitch:4,crush:40,start:50,end:60}})).status,200);
  const state=await(await fetch(origin+'/api/library')).json();assert.equal(state.presets['cat-worker'].settings.pitch,4);assert.equal(state.presets['cat-worker'].settings.start,undefined);assert.equal(state.presets['cat-worker'].settings.end,undefined);assert.equal(state.presets['business-cat'],undefined);
  assert.equal((await post('/api/select',{character:'cat-worker',emotion:'happy',name:result.name})).status,200);
  assert.equal((await post('/api/delete',{character:'cat-worker',emotion:'happy',name:saved.takes[0].name})).status,409);
  const other=createStudio(dir);await new Promise(r=>other.listen(0,'127.0.0.1',r));try{const fresh=await(await fetch(`http://127.0.0.1:${other.address().port}/api/library`)).json();assert.equal(fresh.takes.length,3);assert.equal(fresh.selected['cat-worker/happy'],result.name);assert.equal(fresh.presets['cat-worker'].settings.pitch,4);}finally{await new Promise(r=>other.close(r));}
  assert.equal((await post('/api/delete',{character:'cat-worker',emotion:'happy',name:result.name})).status,200);
  const removed=await(await fetch(origin+'/api/library')).json();assert.equal(removed.takes.length,2);assert.equal(removed.selected['cat-worker/happy'],undefined);assert.ok(!fs.existsSync(path.join(dir,'cat-worker','happy',result.name+'.json')));
  assert.equal((await post('/api/delete',{character:'cat-worker',emotion:'happy',name:'../../bad.wav'})).status,400);
  assert.equal((await post('/api/delete',{character:'cat-worker',emotion:'happy',name:saved.takes[0].name})).status,200);
 }finally{await new Promise(r=>server.close(r));fs.rmSync(dir,{recursive:true,force:true});}
});
test('cleanup trims silence, fades boundaries, and leaves source untouched',()=>{
 const input=new Float32Array(48000);for(let i=12000;i<36000;i++)input[i]=.2*Math.sin(2*Math.PI*440*i/48000);
 const copy=input.slice(),out=processAudio(input,48000,{rate:24000});
 assert.deepEqual(input,copy);assert.ok(out.samples.length<24000*.7);assert.equal(out.samples[0],0);assert.equal(out.samples.at(-1),0);
 assert.ok(out.samples.every(x=>Number.isFinite(x)&&Math.abs(x)<=.981));
 const bytes=new Uint8Array(encodeWav(out.samples,out.rate));assert.equal(decodeWav(bytes).rate,24000);
 assert.throws(()=>processAudio(input,48000,{start:.8,end:.2}));assert.throws(()=>processAudio(input,48000,{pitch:NaN}));
 const normal=processAudio(input,48000,{trim:false}),higher=processAudio(input,48000,{trim:false,pitch:12});assert.equal(higher.samples.length,normal.samples.length/2);
 const retro=processAudio(input,48000,{crush:100,bits:4,hold:12});assert.notDeepEqual(retro.samples,out.samples);
});
test('batch spans emotions, excludes edits and other characters, and reruns without duplicates',async()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'critter-batch-test-')),server=createStudio(dir);
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin=`http://127.0.0.1:${server.address().port}`;
 try{
  const get=async()=>await(await fetch(origin+'/api/library')).json();const initial=await get();const headers={Origin:origin,'X-Studio-Token':initial.token};
  for(const [character,emotion] of [['cat-worker','neutral'],['cat-worker','happy'],['business-cat','happy']]){
   assert.equal((await fetch(`${origin}/api/takes?character=${character}&emotion=${emotion}`,{method:'POST',headers,body:wav()})).status,201);
  }
  const save=async body=>{const r=await fetch(origin+'/api/versions',{method:'POST',headers,body:JSON.stringify(body)});const value=await r.json();if(!r.ok)throw Error(value.error);return value;};
  const preset={settings:{pitch:3,crush:50,rate:24000}};
  const first=await applyVoiceBatch('cat-worker',(await get()).takes,preset,save);assert.equal(first.created,2);assert.equal(first.total,2);assert.equal(first.failed.length,0);
  const second=await applyVoiceBatch('cat-worker',(await get()).takes,preset,save);assert.equal(second.created,0);assert.equal(second.reused,2);
  const after=await get();assert.equal(after.takes.length,5);assert.deepEqual(after.selected,{});
  for(const t of after.takes.filter(t=>t.kind==='original'))assert.deepEqual(fs.readFileSync(path.join(dir,t.character,t.emotion,t.name)),wav());
 }finally{await new Promise(r=>server.close(r));fs.rmSync(dir,{recursive:true,force:true});}
});
test('batch reports partial failures and resets take-specific trim points',async()=>{
 const takes=['neutral','happy'].map(emotion=>({character:'cat-worker',emotion,name:emotion+'.wav',kind:'original'}));let calls=0;
 const result=await applyVoiceBatch('cat-worker',takes,{settings:{start:10,end:11,pitch:2}},async body=>{calls++;assert.equal(body.settings.start,0);assert.equal(body.settings.end,0);if(calls===1)throw Error('Disk full');return {existing:false};});
 assert.equal(calls,2);assert.equal(result.failed.length,1);assert.equal(result.created,1);
 await assert.rejects(()=>applyVoiceBatch('cat-worker',takes,null,()=>{}),/preset/);
});
