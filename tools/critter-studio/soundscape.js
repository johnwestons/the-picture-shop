import {encodePCM} from '/soundscape-dsp.mjs';
const $=id=>document.getElementById(id);
let library,slotId,source=null,rendered=null,dirty=false,needsRender=false,working=false,worker=null,recording=null,recordTimer;
const layers=new Map();let objectUrls=[];
const bytes=n=>n>=1e6?(n/1e6).toFixed(2)+' MB':(n/1000).toFixed(1)+' KB';
const message=s=>{$('message').textContent=s;};
const slot=()=>library.catalog.find(s=>s.id===slotId);
const choice=()=>library.state.slots[slotId]||{selected:null,gain:1,muted:false};
function lock(on){working=on;document.querySelectorAll('button,select,input').forEach(e=>{e.disabled=on;});$('stopAll').disabled=false;$('cancelRender').disabled=false;$('stopRecord').disabled=!recording;$('saveTake').disabled=on||!source||needsRender;}
async function post(endpoint,body){const r=await fetch('/sc/'+endpoint,{method:'POST',headers:{'Content-Type':'application/json','X-Studio-Token':library.token},body:JSON.stringify(body)});const data=await r.json();if(!r.ok)throw Error(data.error);return data;}
async function refresh(){const r=await fetch('/sc/library');if(!r.ok)throw Error('Could not load studio.');library=await r.json();slotId=slotId||library.catalog.find(s=>s.id==='shop-loading_door')?.id||library.catalog[0].id;drawCatalog();drawSlot();}
function drawCatalog(){
 const selectedCategory=$('category').value,q=$('search').value.toLowerCase();$('slots').replaceChildren();
 for(const s of library.catalog.filter(s=>(selectedCategory==='all'||s.bus===selectedCategory)&&s.name.toLowerCase().includes(q))){const b=document.createElement('button');b.textContent=s.name;b.className=s.id===slotId?'selected':'';const label=document.createElement('span');label.textContent=s.bus+' · '+(library.state.slots[s.id]?.selected?'Custom chosen':'Factory');b.append(label);b.onclick=()=>{if(working)return;if(dirty&&!confirm('Switch sound slots and discard the unsaved editor changes?'))return;closeEditor();slotId=s.id;drawCatalog();drawSlot();};$('slots').append(b);}
}
function drawSlot(){
 const s=slot(),c=choice();$('slotTitle').textContent=s.name;$('slotInfo').textContent=`${s.bus} · ${s.loop?'Loops in game':'One-shot / track'}`;
 const chosen=library.takes.find(t=>t.slot===s.id&&t.id===c.selected);
 $('currentName').textContent='Chosen for game: '+(chosen?.label||'Factory sound');
 $('currentAudio').pause();$('currentAudio').src=chosen?.url||'/sc/factory/'+s.id;$('currentAudio').loop=s.loop;
 $('editCurrent').onclick=()=>guard(()=>loadURL(chosen?.url||'/sc/factory/'+s.id,(chosen?.label||s.name)+' variation',chosen?.notes));
 $('slotGain').value=c.gain*100;$('slotGainValue').textContent=Math.round(c.gain*100)+'%';$('slotMute').checked=c.muted;
 $('takes').replaceChildren();
 const factory=document.createElement('div');factory.className='take'+(!c.selected?' chosen':'');
 const factoryName=document.createElement('p');factoryName.textContent=(!c.selected?'★ ':'')+'Factory sound · original';
 const factoryAudio=document.createElement('audio');factoryAudio.controls=true;factoryAudio.preload='none';factoryAudio.src='/sc/factory/'+s.id;
 const factoryEdit=document.createElement('button');factoryEdit.textContent='Tweak factory sound';factoryEdit.onclick=()=>guard(()=>loadURL('/sc/factory/'+s.id,s.name+' variation'));
 factory.append(factoryName,factoryAudio,factoryEdit);$('takes').append(factory);
 const takes=library.takes.filter(t=>t.slot===s.id).sort((a,b)=>b.created.localeCompare(a.created));
 for(const t of takes){const row=document.createElement('div');row.className='take'+(c.selected===t.id?' chosen':'');const name=document.createElement('p');name.textContent=(c.selected===t.id?'★ ':'')+t.label+` · ${t.duration.toFixed(2)} s · ${t.channels===2?'stereo':'mono'} · ${bytes(t.bytes)}`;const a=document.createElement('audio');a.controls=true;a.preload='none';a.src=t.url;const controls=document.createElement('div');controls.className='controls';
  const action=(text,fn)=>{const b=document.createElement('button');b.textContent=text;b.onclick=()=>guard(fn);controls.append(b);};
  action('Tweak a copy',()=>loadURL(t.url,t.label+' variation',t.notes));
  action(c.selected===t.id?'Chosen':'Choose for this slot',async()=>{await saveSlot(t.id);message('Chosen in draft. Apply to game when ready.');});
  action('Delete take',async()=>{if(!confirm(`Permanently delete “${t.label}”?`))return;await post('delete',{slot:s.id,id:t.id});await refresh();message('Take deleted.');});
  const download=document.createElement('a');download.href=t.url;download.download=t.label+'.wav';download.textContent='Download WAV';controls.append(download);row.append(name,a,controls);$('takes').append(row);
 }
 if(!takes.length){const p=document.createElement('p');p.textContent='No saved takes yet. Tweak the factory sound, import a file, or record below.';$('takes').append(p);}
}
async function guard(fn){try{await fn();}catch(e){message(e.message);}}
async function saveSlot(selected=choice().selected){await post('slot',{slot:slotId,selected:selected||null,gain:Number($('slotGain').value)/100,muted:$('slotMute').checked});await refresh();updateLayers();}
function buildMix(){
 $('mix').replaceChildren();for(const bus of ['master','sfx','ambience','music']){const div=document.createElement('div'),label=document.createElement('label'),input=document.createElement('input');label.htmlFor='mix-'+bus;input.id=label.htmlFor;input.type='range';input.min=0;input.max=100;input.value=library.state.mix[bus]*100;label.textContent=bus.toUpperCase()+' · '+input.value+'%';input.oninput=()=>{label.textContent=bus.toUpperCase()+' · '+input.value+'%';updateLayers();};div.append(label,input);$('mix').append(div);}
}
function mix(){return Object.fromEntries(['master','sfx','ambience','music'].map(k=>[k,Number($('mix-'+k).value)/100]));}
function updateLayers(){const m=mix();for(const [id,l]of layers){const c=library.state.slots[id]||{gain:1},s=library.catalog.find(s=>s.id===id);l.audio.volume=Math.min(1,s.base*m.master*m[s.bus]*(c.muted?0:c.gain));}}
function stopAll(){for(const l of layers.values()){l.audio.pause();l.row.remove();}layers.clear();document.querySelectorAll('audio').forEach(a=>a.pause());}
async function audition(){
 const s=slot(),c=choice();$('mixerPanel').open=true;
 if(layers.has(s.id)){const old=layers.get(s.id);old.audio.pause();old.row.remove();layers.delete(s.id);}
 const row=document.createElement('div');row.className='layer';const name=document.createElement('strong');name.textContent=s.name;const audio=document.createElement('audio');audio.controls=true;audio.loop=s.loop||s.bus==='ambience';audio.src=c.selected?`/sc/audio/${s.id}/${c.selected}`:'/sc/factory/'+s.id;
 const loop=document.createElement('label'),check=document.createElement('input');check.type='checkbox';check.checked=audio.loop;check.onchange=()=>audio.loop=check.checked;loop.append(check,document.createTextNode(' Loop in preview'));const remove=document.createElement('button');remove.textContent='Remove layer';remove.onclick=()=>{audio.pause();row.remove();layers.delete(s.id);};row.append(name,audio,loop,remove);$('layers').append(row);layers.set(s.id,{row,audio});updateLayers();await audio.play();message('Preview layers use approximate game cue levels. In-game vehicle levels also respond to speed and engine load.');
}
function revoke(){for(const url of objectUrls)URL.revokeObjectURL(url);objectUrls=[];}
function closeEditor(){if(worker){worker.terminate();worker=null;}source=null;rendered=null;dirty=false;needsRender=false;$('original').pause();$('preview').pause();$('editPanel').hidden=true;revoke();}
async function decode(array){const context=new AudioContext({sampleRate:48000});try{const audio=await context.decodeAudioData(array);if(audio.duration<.1||audio.duration>600)throw Error('Use a clip between 0.1 seconds and 10 minutes.');if(audio.numberOfChannels>2)throw Error('Import mono or stereo audio, not multichannel surround.');return {rate:audio.sampleRate,channels:Array.from({length:audio.numberOfChannels},(_,i)=>audio.getChannelData(i).slice()),duration:audio.duration};}finally{await context.close();}}
async function openSource(data,label,notes=''){
 closeEditor();source=data;dirty=true;$('label').value=label.slice(0,100);$('notes').value=notes||'';$('start').value=0;$('end').value=data.duration;$('end').max=data.duration;
 for(const [id,value]of Object.entries({gain:0,pitch:0,fade:slot().loop?0:.01,crush:0,bits:8}))$(id).value=value;
 for(const id of ['clean','normalize','mono'])$(id).checked=false;$('loopPreview').checked=slot().loop;
 const blob=new Blob([encodePCM(data.channels,data.rate)],{type:'audio/wav'}),url=URL.createObjectURL(blob);objectUrls.push(url);$('original').src=url;$('original').loop=slot().loop;$('preview').hidden=true;$('download').hidden=true;$('saveTake').textContent='Save source as take';$('saveTake').disabled=false;$('editTitle').textContent=slot().name+' / workshop';$('editPanel').hidden=false;
 $('editInfo').textContent=`${data.duration.toFixed(2)} seconds · ${data.channels.length===2?'stereo':'mono'} · ${data.rate/1000} kHz. Save source or render edits first.`;
 const canvas=$('wave'),g=canvas.getContext('2d');g.clearRect(0,0,canvas.width,canvas.height);g.strokeStyle='#e2bd74';g.beginPath();const samples=data.channels[0],stride=Math.max(1,Math.floor(samples.length/canvas.width));for(let x=0;x<canvas.width;x++){let peak=0;for(let j=x*stride;j<Math.min(samples.length,(x+1)*stride);j++)peak=Math.max(peak,Math.abs(samples[j]));g.moveTo(x,50-peak*45);g.lineTo(x,50+peak*45);}g.stroke();$('editPanel').scrollIntoView({behavior:'smooth',block:'start'});
}
async function loadURL(url,label,notes){if(dirty&&!confirm('Replace the unsaved editor changes?'))return;stopAll();lock(true);message('Loading audio…');try{const r=await fetch(url);if(!r.ok)throw Error('Could not load this sound.');const data=await decode(await r.arrayBuffer());await openSource(data,label,notes);dirty=false;message('Source loaded. Tweak the controls, preview, and save a new version.');}finally{lock(false);}}
function invalidate(){rendered=null;dirty=true;needsRender=true;$('preview').pause();$('preview').hidden=true;$('download').hidden=true;$('saveTake').disabled=true;$('saveTake').textContent='Preview edits before saving';}
const effectIds=['start','end','gain','pitch','fade','crush','bits','clean','normalize','mono'];for(const id of effectIds)$(id).oninput=invalidate;
$('label').oninput=$('notes').oninput=()=>{dirty=true;};
$('loopPreview').onchange=()=>{$('preview').loop=$('original').loop=$('loopPreview').checked;};
$('render').onclick=()=>{
 if(!source)return;stopAll();lock(true);message('Rendering in the background…');$('cancelRender').hidden=false;
 const settings=Object.fromEntries(effectIds.map(k=>[k,['clean','normalize','mono'].includes(k)?$(k).checked:Number($(k).value)]));
 worker=new Worker('/soundscape-worker.js',{type:'module'});
 const finish=()=>{worker?.terminate();worker=null;$('cancelRender').hidden=true;lock(false);};
 worker.onerror=e=>{message('Processing failed: '+e.message);finish();};
 worker.onmessage=({data})=>{if(data.error){message(data.error);finish();return;}rendered=new Blob([data.wav],{type:'audio/wav'});needsRender=false;const url=URL.createObjectURL(rendered);objectUrls.push(url);$('preview').src=url;$('preview').loop=$('loopPreview').checked;$('preview').hidden=false;$('download').href=url;$('download').download=($('label').value||'sound')+'.wav';$('download').hidden=false;$('saveTake').textContent='Save edited take';dirty=true;finish();$('saveTake').disabled=false;message(`Preview ready · ${bytes(rendered.size)}${data.clipped?' · Clipping detected: lower gain or enable normalization before saving.':''}`);$('preview').play().catch(()=>{});};
 worker.postMessage({channels:source.channels,rate:source.rate,settings});
};
$('cancelRender').onclick=()=>{worker?.terminate();worker=null;$('cancelRender').hidden=true;lock(false);$('saveTake').disabled=true;message('Processing canceled. Source is intact.');};
$('saveTake').onclick=()=>guard(async()=>{if(!source)return;lock(true);try{const blob=rendered||new Blob([encodePCM(source.channels,source.rate)],{type:'audio/wav'});const query=new URLSearchParams({slot:slotId,label:$('label').value||'Untitled take',notes:$('notes').value});const r=await fetch('/sc/upload?'+query,{method:'POST',headers:{'Content-Type':'audio/wav','X-Studio-Token':library.token},body:blob});const data=await r.json();if(!r.ok)throw Error(data.error);dirty=false;await refresh();message(data.existing?'Identical take already exists; no duplicate saved.':'Take saved to the project. Choose it for this slot when ready.');}finally{lock(false);}});
$('importFile').onchange=()=>guard(async()=>{const file=$('importFile').files[0];if(!file)return;if(file.size>116000000)throw Error('File exceeds 116 MB.');if(dirty&&!confirm('Replace unsaved editor changes?'))return;lock(true);try{message('Decoding imported audio…');await openSource(await decode(await file.arrayBuffer()),file.name.replace(/\.[^.]+$/,''),'Imported: '+file.name);message('Imported into the editor. Preview or save the source take.');}finally{lock(false);$('importFile').value='';}});
$('record').onclick=()=>guard(async()=>{
 if(dirty&&!confirm('Replace unsaved editor changes with a new recording?'))return;stopAll();lock(true);let stream,context;
 try{stream=await navigator.mediaDevices.getUserMedia({audio:{channelCount:1,echoCancellation:false,noiseSuppression:false,autoGainControl:false}});context=new AudioContext({sampleRate:48000});await context.resume();await context.audioWorklet.addModule('/capture.js');const node=new AudioWorkletNode(context,'critter-capture'),input=context.createMediaStreamSource(stream);recording={stream,context,node,input,chunks:[],count:0};
 node.port.onmessage=({data})=>{if(!recording)return;recording.chunks.push(data);recording.count+=data.length;if(recording.count>=context.sampleRate*120)stopRecording();};input.connect(node);node.connect(context.destination);$('stopRecord').disabled=false;recordTimer=setInterval(()=>{$('recordTime').textContent=(recording.count/context.sampleRate).toFixed(1)+' s / 120 s';},100);message('Recording microphone into '+slot().name+'.');
 }catch(e){stream?.getTracks().forEach(t=>t.stop());await context?.close();lock(false);throw e;}
});
async function stopRecording(){const r=recording;if(!r)return;recording=null;clearInterval(recordTimer);r.node.disconnect();r.input.disconnect();r.stream.getTracks().forEach(t=>t.stop());await r.context.close();try{if(r.count<r.context.sampleRate*.1)throw Error('Recording too short.');const samples=new Float32Array(r.count);let offset=0;for(const c of r.chunks){samples.set(c,offset);offset+=c.length;}await openSource({channels:[samples],rate:r.context.sampleRate,duration:samples.length/r.context.sampleRate},slot().name+' recording','Original microphone recording');message('Recording ready. Preview or save the take.');}catch(e){message(e.message);}finally{lock(false);}}
$('stopRecord').onclick=stopRecording;
$('closeEdit').onclick=()=>{if(dirty&&!confirm('Discard unsaved editor changes?'))return;closeEditor();};
$('category').onchange=$('search').oninput=drawCatalog;
$('slotGain').oninput=()=>{$('slotGainValue').textContent=$('slotGain').value+'%';};
$('saveSlot').onclick=()=>guard(async()=>{await saveSlot();message('Slot mix saved in draft.');});
$('factory').onclick=()=>guard(async()=>{await saveSlot(null);message('Factory sound selected in draft. Apply to game to publish.');});
$('audition').onclick=()=>guard(audition);$('stopAll').onclick=stopAll;
$('playCurrent').onclick=()=>guard(async()=>{$('currentAudio').currentTime=0;await $('currentAudio').play();});
// A/B listening should never accidentally double the volume. Layering is explicit.
document.addEventListener('play',e=>{if(e.target.tagName!=='AUDIO')return;const layered=[...layers.values()].some(l=>l.audio===e.target);document.querySelectorAll('audio').forEach(a=>{if(a!==e.target&&(!layered||![...layers.values()].some(l=>l.audio===a)))a.pause();});},true);
document.addEventListener('error',e=>{if(e.target.tagName==='AUDIO')message('This audio could not be played. Try reloading the studio or import a replacement.');},true);
$('saveMix').onclick=()=>guard(async()=>{await post('mix',mix());message('Mix draft saved.');});
$('apply').onclick=()=>guard(async()=>{lock(true);try{await post('mix',mix());await saveSlot();const result=await post('apply',{});message(`Applied to game: ${result.files.length} selected audio files (${bytes(result.bytes)}). Restart the game to hear this soundscape.`);}finally{lock(false);}});
$('publishTop').onclick=()=>$('apply').click();
window.addEventListener('beforeunload',e=>{if(dirty||working||recording){e.preventDefault();e.returnValue='';}});
refresh().then(()=>{buildMix();message('Ready. Pick a game sound to record, import, edit, or audition.');}).catch(e=>message(e.message));
