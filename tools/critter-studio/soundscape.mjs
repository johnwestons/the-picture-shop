import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {encodePCM} from './soundscape-dsp.mjs';
// The same oscillators and envelopes used by the game's generated cues.
export function generatedFactory(id){
 const horn=id==='commute-horn',ringback=id==='shop-phone_ringback_loop';
 if(!horn&&!ringback&&id!=='shop-phone_ring_loop')throw Error('Unknown generated sound.');
 const rate=48000,duration=horn?.5:ringback?1:2,samples=new Float32Array(rate*duration);
 const intervals=ringback?[[0,.38],[.52,.96]]:[[0,.38],[.52,.90]];
 for(let i=0;i<samples.length;i++){const t=i/rate;
  if(horn)samples[i]=(Math.sin(t*Math.PI*2*392)+.72*Math.sin(t*Math.PI*2*494))*.28*Math.min(1,t/.012);
  else {let envelope=0;for(const [start,end]of intervals)if(t>=start&&t<=end)envelope=Math.min(1,(t-start)/.015,(end-t)/.015);samples[i]=.22*envelope*(Math.sin(2*Math.PI*440*t)+Math.sin(2*Math.PI*480*t));}
 }
 return Buffer.from(encodePCM([samples],rate));
}
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const title=s=>s.replace(/[-_]/g,' ').replace(/\b\w/g,c=>c.toUpperCase());
export function soundCatalog(root){
 const slots=[];
 const shop=fs.readFileSync(path.join(root,'src/sound.lua'),'utf8');
 for(const m of shop.matchAll(/(\w+)\s*=\s*\{\s*path\s*=\s*"(assets\/audio\/sfx\/[^"\n]+)"([\s\S]*?)\}/g))slots.push({id:'shop-'+m[1],name:title(m[1]),path:m[2],bus:m[1].includes('ambience')?'ambience':'sfx',loop:/loop\s*=\s*true/.test(m[3]),base:Number(m[3].match(/volume\s*=\s*([.\d]+)/)?.[1]||1)});
 for(const name of ['engine-1400','engine-3000','engine-5000','engine-7500','wind','tires','intake','brake','ignition','shutdown','shift','impact','nature'])slots.push({id:'commute-'+name,name:'Road · '+title(name),path:'assets/audio/commute/'+(name==='nature'?'forest-ambience.mp3':name+'.wav'),bus:['wind','nature'].includes(name)?'ambience':'sfx',loop:!['ignition','shutdown','shift','impact'].includes(name),base:.3});
 const jukebox=fs.readFileSync(path.join(root,'src/jukebox.lua'),'utf8');
 for(const m of jukebox.matchAll(/file\s*=\s*"([\w_]+)\.wav",\s*title\s*=\s*"([^"]+)"/g))slots.push({id:'music-'+m[1],name:m[2],path:'assets/audio/music/vibes/'+m[1]+'.wav',bus:'music',loop:false,base:.24});
 for(const [id,name,loop] of [['shop-phone_ring_loop','Phone ring',true],['shop-phone_ringback_loop','Phone ringback',true],['commute-horn','Vehicle horn',true]])slots.push({id,name,bus:'sfx',path:null,loop,base:.4});
 return slots;
}
export function inspectPCM(b){
 if(b.length<44||b.toString('ascii',0,4)!=='RIFF'||b.toString('ascii',8,12)!=='WAVE'||b.readUInt32LE(4)!==b.length-8)throw Error('Upload a PCM WAV produced by the studio.');
 let format,frames=0;
 for(let p=12;p+8<=b.length;){const n=b.readUInt32LE(p+4),tag=b.toString('ascii',p,p+4);if(p+8+n>b.length)throw Error('Truncated WAV.');
  if(tag==='fmt '){if(n<16)throw Error('Invalid format.');format={code:b.readUInt16LE(p+8),channels:b.readUInt16LE(p+10),rate:b.readUInt32LE(p+12),bytes:b.readUInt32LE(p+16),align:b.readUInt16LE(p+20),bits:b.readUInt16LE(p+22)};}
  if(tag==='data'){if(!format||n%format.align)throw Error('Invalid data alignment.');frames+=n/format.align;}p+=8+n+(n%2);
 }
 if(!format||format.code!==1||![1,2].includes(format.channels)||![24000,44100,48000].includes(format.rate)||format.bits!==16||format.align!==format.channels*2||format.bytes!==format.rate*format.align)throw Error('Use 16-bit mono/stereo PCM at 24, 44.1 or 48 kHz.');
 const duration=frames/format.rate;if(duration<.1||duration>600)throw Error('Keep audio between 0.1 seconds and 10 minutes.');return {...format,duration};
}
export function createSoundscape(root,storage=path.join(root,'assets/source/soundscape-studio')){
 const slots=soundCatalog(root),getSlot=id=>slots.find(s=>s.id===id),stateFile=path.join(storage,'studio.json');
 const empty=()=>({slots:{},mix:{master:1,sfx:1,ambience:1,music:1}});
 const read=()=>{try{return JSON.parse(fs.readFileSync(stateFile,'utf8'));}catch(e){if(e.code==='ENOENT')return empty();throw e;}};
 const write=state=>{fs.mkdirSync(storage,{recursive:true});fs.writeFileSync(stateFile+'.tmp',JSON.stringify(state,null,2));fs.renameSync(stateFile+'.tmp',stateFile);};
 const valid=id=>typeof id==='string'&&/^[a-f0-9]{64}$/.test(id);
 const takeFile=(slot,id)=>{if(!getSlot(slot)||!valid(id))throw Error('Unknown audio take.');return path.join(storage,slot,id+'.wav');};
 const takes=()=>slots.flatMap(s=>{const dir=path.join(storage,s.id);if(!fs.existsSync(dir))return [];return fs.readdirSync(dir).filter(n=>/^[a-f0-9]{64}\.json$/.test(n)).flatMap(n=>{const t=JSON.parse(fs.readFileSync(path.join(dir,n),'utf8'));return fs.existsSync(takeFile(s.id,t.id))?[{...t,slot:s.id,url:`/sc/audio/${s.id}/${t.id}`}]:[];});});
 const jsonBody=async req=>{let b='';for await(const c of req){b+=c;if(b.length>32768)throw Error('Settings too large.');}return JSON.parse(b);};
 return async function handle(req,res,url,token,origin){
  if(!url.pathname.startsWith('/sc/'))return false;
  const send=(status,data,type='application/json')=>{res.writeHead(status,{'Content-Type':type,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(type==='application/json'?JSON.stringify(data):data);};
  try{
   if(req.method==='GET'&&url.pathname==='/sc/library'){const state=read();send(200,{catalog:slots,takes:takes(),state,token});return true;}
   if(req.method==='GET'&&url.pathname.startsWith('/sc/factory/')){const s=getSlot(url.pathname.slice(12));if(!s)throw Error('Unknown sound slot.');send(200,s.path?fs.readFileSync(path.join(root,s.path)):generatedFactory(s.id),s.path?.endsWith('.mp3')?'audio/mpeg':'audio/wav');return true;}
   if(req.method==='GET'&&url.pathname.startsWith('/sc/audio/')){const [slot,id,...extra]=url.pathname.slice(10).split('/');if(extra.length)throw Error('Unknown take.');send(200,fs.readFileSync(takeFile(slot,id)),'audio/wav');return true;}
   if(req.method!=='POST'){send(404,{error:'Not found.'});return true;}
   if(req.headers.origin!==origin||req.headers['x-studio-token']!==token){send(403,{error:'Reload the studio before saving.'});return true;}
   if(url.pathname==='/sc/upload'){
    const slot=url.searchParams.get('slot');if(!getSlot(slot))throw Error('Choose a sound slot.');
    let size=0;const chunks=[];for await(const c of req){size+=c.length;if(size>116000000)throw Error('Maximum audio upload is 116 MB / 10 minutes.');chunks.push(c);}
    const b=Buffer.concat(chunks),info=inspectPCM(b),id=hash(b),file=takeFile(slot,id),exists=fs.existsSync(file);fs.mkdirSync(path.dirname(file),{recursive:true});
    if(!exists){fs.writeFileSync(file,b,{flag:'wx'});fs.writeFileSync(file.replace('.wav','.json'),JSON.stringify({id,label:(url.searchParams.get('label')||'Untitled take').slice(0,100),notes:(url.searchParams.get('notes')||'').slice(0,1000),created:new Date().toISOString(),bytes:b.length,...info},null,2));}
    send(exists?200:201,{id,existing:exists});return true;
   }
   const body=await jsonBody(req),state=read();
   if(url.pathname==='/sc/slot'){
    if(!getSlot(body.slot))throw Error('Unknown sound slot.');
    if(typeof body.gain!=='number'||!Number.isFinite(body.gain)||body.gain<0||body.gain>1)throw Error('Gain must be 0–100%.');
    if(body.selected!==null&&!fs.existsSync(takeFile(body.slot,body.selected)))throw Error('Selected take is missing.');
    state.slots[body.slot]={selected:body.selected,gain:body.gain,muted:body.muted===true};write(state);send(200,{saved:true});return true;
   }
   if(url.pathname==='/sc/mix'){
    for(const k of ['master','sfx','ambience','music'])if(typeof body[k]!=='number'||!Number.isFinite(body[k])||body[k]<0||body[k]>1)throw Error('Mixer levels must be 0–100%.');
    state.mix=Object.fromEntries(['master','sfx','ambience','music'].map(k=>[k,body[k]]));write(state);send(200,{saved:true});return true;
   }
   if(url.pathname==='/sc/delete'){
    const file=takeFile(body.slot,body.id);if(state.slots[body.slot]?.selected===body.id)throw Error('Choose another take or Factory before deleting this selected take.');
    fs.unlinkSync(file);fs.unlinkSync(file.replace('.wav','.json'));send(200,{deleted:true});return true;
   }
   if(url.pathname==='/sc/apply'){
    const dest=path.join(root,'assets/audio/custom');fs.mkdirSync(dest,{recursive:true});const entries={},files=[],credits=[];let bytes=0;
    for(const s of slots){const choice=state.slots[s.id]||{};const entry={gain:choice.muted?0:choice.gain??1,bus:s.bus};
     if(choice.selected){const file=takeFile(s.id,choice.selected),b=fs.readFileSync(file);inspectPCM(b);if(hash(b)!==choice.selected)throw Error('Audio changed on disk. Import it again.');
      const rel=`assets/audio/custom/${choice.selected}.wav`;if(!files.includes(rel)){fs.writeFileSync(path.join(root,rel),b);files.push(rel);bytes+=b.length;}entry.path=rel;
      const metadata=JSON.parse(fs.readFileSync(file.replace('.wav','.json'),'utf8'));credits.push({slot:s.id,path:rel,label:metadata.label,notes:metadata.notes});
     }entries[s.id]=entry;
    }
    const lua='-- Published by the soundscape studio. Draft recordings are excluded.\nreturn {mix={'+Object.entries(state.mix).map(([k,v])=>`${k}=${v}`).join(',')+'},slots={'+Object.entries(entries).map(([k,v])=>`["${k}"]={gain=${v.gain},bus="${v.bus}"${v.path?`,path="${v.path}"`:''}}`).join(',')+'}}\n';
    fs.writeFileSync(path.join(dest,'manifest.lua.tmp'),lua);fs.renameSync(path.join(dest,'manifest.lua.tmp'),path.join(dest,'manifest.lua'));
    const manifest={files,bytes,credits,luaSha256:hash(lua),published:new Date().toISOString()};fs.writeFileSync(path.join(dest,'manifest.json.tmp'),JSON.stringify(manifest,null,2));fs.renameSync(path.join(dest,'manifest.json.tmp'),path.join(dest,'manifest.json'));
    send(200,{applied:true,...manifest});return true;
   }
   send(404,{error:'Unknown studio action.'});
  }catch(e){send(e.code==='ENOENT'?404:400,{error:e.message});}
  return true;
 };
}
