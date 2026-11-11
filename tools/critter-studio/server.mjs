import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {decodeWav,encodeWav,processAudio,settings} from './effects.mjs';
import {createSoundscape} from './soundscape.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
export const emotions = ['neutral','greeting','happy','curious','agreement','disagreement','surprised','annoyed','thanks','goodbye','worried','sad'];
export function roster() {
  const names = {'rabbit-worker':'Player / Rabbit','tan-cat':'Tan Cat','business-dragon':'Business Dragon',grandpa:'Grandpa'};
  for (const source of ['src/worker_catalog.lua','src/commute/town_characters.lua']) {
    for (const m of fs.readFileSync(path.join(root, source),'utf8').matchAll(/name\s*=\s*["']([^"']+)["']\s*,\s*character\s*=\s*["']([^"']+)["']/g)) names[m[2]]=m[1];
  }
  const ids = new Set(Object.keys(names));
  for (const file of fs.readdirSync(path.join(root,'character-motion'))) {
    const data=JSON.parse(fs.readFileSync(path.join(root,'character-motion',file),'utf8'));
    if(data.character && !/cart|pallet|motorcycle|rider/.test(data.character)) ids.add(data.character);
  }
  return [...ids].sort().map(id=>({id,name:names[id] || id.split('-').map(s=>s[0].toUpperCase()+s.slice(1)).join(' ')}));
}
export function validateWav(b, allowedRates=[48000]) {
  if(b.length<46 || b.toString('ascii',0,4)!=='RIFF' || b.toString('ascii',8,12)!=='WAVE' || b.readUInt32LE(4)!==b.length-8) throw Error('Invalid WAV file.');
  let fmt=false, samples=0,rate=0;
  for(let p=12;p+8<=b.length;) {
    const size=b.readUInt32LE(p+4), end=p+8+size;
    if(end>b.length) throw Error('Truncated WAV.');
    const tag=b.toString('ascii',p,p+4);
    if(tag==='fmt ') {
      rate=size>=16?b.readUInt32LE(p+12):0;
      if(size<16 || b.readUInt16LE(p+8)!==1 || b.readUInt16LE(p+10)!==1 || !allowedRates.includes(rate) || b.readUInt32LE(p+16)!==rate*2 || b.readUInt16LE(p+20)!==2 || b.readUInt16LE(p+22)!==16) throw Error('Unsupported PCM WAV format.');
      fmt=true;
    }
    if(tag==='data') {if(size%2) throw Error('Invalid sample size.'); samples+=size/2;}
    p=end+(size%2);
  }
  if(!fmt || samples<rate*.1 || samples>rate*120) throw Error('Record between 0.1 and 120 seconds.');
  return samples/rate;
}
export function createStudio(storage=path.join(root,'assets/audio/voices')) {
  const soundscape=createSoundscape(root);
  const characters=roster(), token=crypto.randomBytes(24).toString('hex');
  const validName=n=>/^(take|edit)-[\w-]+\.wav$/.test(n);
  const validPair=(c,e)=>characters.some(x=>x.id===c)&&emotions.includes(e);
  const statePath=path.join(storage,'studio.json');
  function readState(){try{return JSON.parse(fs.readFileSync(statePath,'utf8'));}catch(e){if(e.code==='ENOENT')return {presets:{},selected:{}};throw e;}}
  function writeState(state){fs.mkdirSync(storage,{recursive:true});fs.writeFileSync(statePath+'.tmp',JSON.stringify(state,null,2));fs.renameSync(statePath+'.tmp',statePath);}
  function library() {
    const takes=[];
    for(const c of characters) for(const emotion of emotions) {
      const dir=path.join(storage,c.id,emotion);
      if(!fs.existsSync(dir)) continue;
      for(const name of fs.readdirSync(dir).filter(validName)) {
        const b=fs.readFileSync(path.join(dir,name));
        let metadata={};try{metadata=JSON.parse(fs.readFileSync(path.join(dir,name+'.json'),'utf8'));}catch{}
        takes.push({character:c.id,emotion,name,kind:name.startsWith('edit-')?'edited':'original',label:metadata.label,source:metadata.source,settings:metadata.settings,bytes:b.length,seconds:validateWav(b,[24000,48000]),created:fs.statSync(path.join(dir,name)).mtime.toISOString(),url:`/audio/${c.id}/${emotion}/${name}`});
      }
    }
    return takes.sort((a,b)=>b.created.localeCompare(a.created));
  }
  const server=http.createServer(async(req,res)=>{
    const send=(code,data,type='application/json')=>{res.writeHead(code,{'Content-Type':type,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(type==='application/json'?JSON.stringify(data):data);};
    try {
      const host=`127.0.0.1:${server.address().port}`;
      if(req.headers.host!==host) return send(403,{error:'Use the local studio address.'});
      const url=new URL(req.url,`http://${host}`);
      if(await soundscape(req,res,url,token,`http://${host}`))return;
      if(req.method==='GET' && url.pathname==='/api/library') return send(200,{version:3,characters,emotions,takes:library(),...readState(),directory:storage,token});
      if(req.method==='POST' && ['/api/preset','/api/select','/api/delete'].includes(url.pathname)) {
        if(req.headers.origin!==`http://${host}` || req.headers['x-studio-token']!==token)return send(403,{error:'Reload the studio before changing the library.'});
        let text='';for await(const chunk of req){text+=chunk;if(text.length>8192)return send(413,{error:'Request too large.'});}
        const body=JSON.parse(text),{character,emotion,name}=body;
        if(!characters.some(c=>c.id===character))return send(400,{error:'Unknown character.'});
        const state=readState();
        if(url.pathname==='/api/preset'){
          const voice=settings({...body.settings,start:0,end:1},1);delete voice.start;delete voice.end;
          state.presets[character]={settings:voice,updated:new Date().toISOString()};writeState(state);
          return send(200,{saved:true});
        }
        if(!validPair(character,emotion)||typeof name!=='string'||!validName(name))return send(400,{error:'Invalid take.'});
        const file=path.join(storage,character,emotion,name);
        if(!fs.existsSync(file))return send(404,{error:'Take no longer exists. Refresh the library.'});
        const key=`${character}/${emotion}`;
        if(url.pathname==='/api/select'){
          if(body.clear===true)delete state.selected[key];else state.selected[key]=name;
          writeState(state);return send(200,{saved:true});
        }
        const dependents=library().filter(t=>t.character===character&&t.emotion===emotion&&t.source===name);
        if(dependents.length)return send(409,{error:`This source is used by ${dependents.length} edited version(s). Delete those versions first so their editable source is not lost.`});
        // Clear the pointer first; failure can never leave a selected missing file.
        if(state.selected[key]===name){delete state.selected[key];writeState(state);}
        fs.unlinkSync(file);
        if(fs.existsSync(file+'.json'))fs.unlinkSync(file+'.json');
        return send(200,{deleted:true});
      }
      if(req.method==='POST' && url.pathname==='/api/versions') {
        if(req.headers.origin!==`http://${host}` || req.headers['x-studio-token']!==token) return send(403,{error:'Reload the studio before saving.'});
        let text='';for await(const chunk of req){text+=chunk;if(text.length>8192)return send(413,{error:'Settings too large.'});}
        const body=JSON.parse(text),{character,emotion,source}=body;
        if(!validPair(character,emotion)||typeof source!=='string'||!validName(source))return send(400,{error:'Invalid source take.'});
        const label=typeof body.label==='string'?body.label.trim().slice(0,60):'';
        if(!label)return send(400,{error:'Name this version before saving.'});
        const dir=path.join(storage,character,emotion),original=fs.readFileSync(path.join(dir,source));
        validateWav(original,[24000,48000]);
        const decoded=decodeWav(original),processed=processAudio(decoded.samples,decoded.rate,body.settings);
        const data=Buffer.from(encodeWav(processed.samples,processed.rate));
        // Identical processed audio reuses its file, even across repeated Save clicks.
        const hash=crypto.createHash('sha256').update(data).digest('hex').slice(0,24),name=`edit-${hash}.wav`;
        const destination=path.join(dir,name);
        const exists=fs.existsSync(destination);
        if(!exists){
          fs.writeFileSync(destination,data,{flag:'wx'});
          try{fs.writeFileSync(destination+'.json',JSON.stringify({label,source,settings:processed.settings},null,2),{flag:'wx'});}catch(e){fs.unlinkSync(destination);throw e;}
        }
        return send(exists?200:201,{name,existing:exists,bytes:data.length,seconds:processed.samples.length/processed.rate});
      }
      if(req.method==='POST' && url.pathname==='/api/takes') {
        if(req.headers.origin!==`http://${host}` || req.headers['x-studio-token']!==token) return send(403,{error:'Reload the studio before saving.'});
        const character=url.searchParams.get('character'),emotion=url.searchParams.get('emotion');
        if(!characters.some(c=>c.id===character) || !emotions.includes(emotion)) return send(400,{error:'Choose a valid character and emotion.'});
        const chunks=[];let size=0;
        for await(const chunk of req) {size+=chunk.length;if(size>120*96000+1024) {send(413,{error:'Take exceeds two minutes.'});return;}chunks.push(chunk);}
        const data=Buffer.concat(chunks),seconds=validateWav(data);
        const dir=path.join(storage,character,emotion);fs.mkdirSync(dir,{recursive:true});
        const name=`take-${new Date().toISOString().replace(/[:.]/g,'-')}-${crypto.randomBytes(3).toString('hex')}.wav`;
        fs.writeFileSync(path.join(dir,name),data,{flag:'wx'});
        return send(201,{name,seconds});
      }
      if(req.method==='GET' && url.pathname.startsWith('/audio/')) {
        const parts=url.pathname.slice(7).split('/');
        if(parts.length!==3 || !validPair(parts[0],parts[1]) || !validName(parts[2])) return send(404,{error:'Unknown take.'});
        return send(200,fs.readFileSync(path.join(storage,...parts)),'audio/wav');
      }
      const files={'/':'index.html','/app.js':'app.js','/capture.js':'capture.js','/style.css':'style.css','/effects.mjs':'effects.mjs','/batch.mjs':'batch.mjs','/soundscape':'soundscape.html','/soundscape.js':'soundscape.js','/soundscape-worker.js':'soundscape-worker.js','/soundscape-dsp.mjs':'soundscape-dsp.mjs'};
      if(req.method==='GET' && files[url.pathname]) return send(200,fs.readFileSync(path.join(here,files[url.pathname])),/\.(mjs|js)$/.test(url.pathname)?'text/javascript':url.pathname.endsWith('.css')?'text/css':'text/html');
      send(404,{error:'Not found.'});
    } catch(e) {send(e.code==='ENOENT'?404:400,{error:e.message});}
  });
  return server;
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const port=Number(process.env.CRITTER_STUDIO_PORT || 43127);
  const server=createStudio();
  server.on('error',e=>{console.error(e.code==='EADDRINUSE'?`Studio already running? Open http://127.0.0.1:${port}`:e);process.exitCode=1;});
  server.listen(port,'127.0.0.1',()=>console.log(`Critter Recording Studio: http://127.0.0.1:${port}`));
}
