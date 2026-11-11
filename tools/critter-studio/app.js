import {defaults,decodeWav,encodeWav,processAudio} from '/effects.mjs';
import {applyVoiceBatch} from '/batch.mjs';
const $=id=>document.getElementById(id);
let editing=null,editData=null,editBlob=null,editURL=null,editDirty=false;
let library,ctx,stream,node,source,chunks=[],count=0,recording=false,busy=false,draft=null,draftURL,started,tick;
const title=s=>s[0].toUpperCase()+s.slice(1);
const hints={neutral:'A gentle conversational murmur or a few little syllables.',greeting:'A welcoming chirp — like spotting a friend at the door.',happy:'A delighted squeak, chuckle, or cheerful trill.',curious:'A questioning hum with a little upward lift.',surprised:'A quick gasp, peep, or startled squeak.',annoyed:'A grumble or impatient huff.',sad:'A soft, drooping whimper or sigh.',worried:'An uncertain squeak or nervous murmur.',agreement:'An upbeat little “mm-hm” sound.',disagreement:'A firm, short grumble or head-shake sound.',thanks:'A warm, appreciative chirrup.',goodbye:'A friendly little farewell trill.'};
function status(text){$('status').textContent=text;}
function lock(){for(const id of ['character','emotion','microphone','refresh','voiceImport']) $(id).disabled=recording||busy||!!draft||!!editing;$('record').disabled=recording||busy||!!draft||!!editing;$('stop').disabled=!recording||busy;for(const b of document.querySelectorAll('.check,.edit-take,.take-action'))b.disabled=recording||busy||!!draft||!!editing;$('batchVoice').disabled=recording||busy||!!draft||!!editing||!library?.presets?.[$('character').value]||!library?.takes.some(t=>t.character===$('character').value&&t.kind==='original');}
function render(){
  const c=$('character').value,e=$('emotion').value,all=library.takes.filter(t=>t.character===c),takes=all.filter(t=>t.emotion===e);
  $('heading').textContent=library.characters.find(x=>x.id===c)?.name || 'Critter';
  $('prompt').textContent=c==='grandpa'
    ? (e==='greeting'?'Grandpa uses this sound for his first porch greeting. Record a warm welcome.'
      : e==='neutral'?'Grandpa uses this sound for the rest of his opening conversation. Record a gentle speaking murmur.'
      : hints[e]+' This emotion is available for later Grandpa conversations.')
    : hints[e];
  $('libraryTitle').textContent=`${title(e)} · ${takes.length} saved take${takes.length===1?'':'s'}`;
  $('progress').textContent=`${new Set(all.map(t=>t.emotion)).size} of ${library.emotions.length} sounds recorded`;
  $('voicePresetStatus').textContent=(library.presets?.[c]?'Character voice saved. It loads automatically when editing an original take.':'No character voice preset yet. Save one from the effects editor.')+' '+library.emotions.filter(emotion=>library.selected?.[`${c}/${emotion}`]).length+' sounds have a chosen take.';
  $('directory').textContent=`Saving to: ${library.directory} / ${c} / ${e}`;
  $('checklist').replaceChildren();
  for(const emotion of library.emotions){const b=document.createElement('button');b.className='check'+(e===emotion?' active':'');b.textContent=title(emotion);const s=document.createElement('span');const n=all.filter(t=>t.emotion===emotion).length;s.textContent=n?`${n} take${n===1?'':'s'}`:'To record';b.append(s);b.onclick=()=>{$('emotion').value=emotion;render();};$('checklist').append(b);}
  $('takes').replaceChildren();
  $('storageSummary').textContent='Project sound library: '+formatBytes(library.takes.reduce((sum,t)=>sum+t.bytes,0))+' · '+library.takes.length+' files. Recordings and edits stay out of game builds until explicitly integrated. Common conversation sounds appear first in the checklist.';
  if(!takes.length){const p=document.createElement('p');p.textContent='No takes yet. This sound is waiting for its voice.';$('takes').append(p);}
  takes.forEach((t,i)=>{const row=document.createElement('div');row.className='take';const meta=document.createElement('div');meta.className='take-meta';meta.textContent=`${i===0?'Latest · ':''}${new Date(t.created).toLocaleString()} · ${t.seconds.toFixed(1)}s`;const a=document.createElement('a');a.href=t.url;a.download=t.name;a.textContent='WAV ↓';meta.append(a);const player=document.createElement('audio');player.controls=true;player.preload='none';player.src=t.url;const edit=document.createElement('button');edit.className='edit-take';edit.textContent='Tweak this take';edit.onclick=()=>openEditor(t);const tag=document.createElement('div');tag.className='muted';tag.textContent=(t.kind==='edited'?'Edited · '+(t.label||'Version'):'Original recording')+' · '+formatBytes(t.bytes);const chosen=library.selected?.[`${t.character}/${t.emotion}`]===t.name;const pick=document.createElement("button");pick.className="take-action";pick.textContent=chosen?"★ Chosen take · clear":"Use this take";pick.onclick=()=>chooseTake(t,chosen);const remove=document.createElement("button");remove.className="take-action danger";remove.textContent="Delete take";remove.onclick=()=>deleteTake(t);const actions=document.createElement("div");actions.className="controls";actions.append(edit,pick,remove);if(chosen){row.classList.add("chosen");tag.textContent="★ CHOSEN FOR THIS SOUND · "+tag.textContent;}row.append(meta,tag,player,actions);$('takes').append(row);});lock();
}
async function refresh(){const response=await fetch('/api/library');if(!response.ok)throw Error('Cannot load the take library.');library=await response.json();const character=$('character').value,emotion=$('emotion').value;$('character').replaceChildren(...library.characters.map(c=>new Option(c.name,c.id)));if(library.characters.some(c=>c.id===character))$('character').value=character;$('emotion').replaceChildren(...library.emotions.map(e=>new Option(title(e),e)));if(library.emotions.includes(emotion))$('emotion').value=emotion;render();}
async function devices(){const selected=$('microphone').value;const list=await navigator.mediaDevices.enumerateDevices();$('microphone').replaceChildren(new Option('System default',''));for(const d of list.filter(d=>d.kind==='audioinput'&&d.deviceId))$('microphone').add(new Option(d.label||'Microphone',d.deviceId));if([...$('microphone').options].some(o=>o.value===selected))$('microphone').value=selected;}
function cleanup(){clearInterval(tick);if(node)node.disconnect();if(source)source.disconnect();stream?.getTracks().forEach(t=>t.stop());stream=null;node=null;source=null;}
function wave(samples){const canvas=$('wave'),g=canvas.getContext('2d');g.clearRect(0,0,canvas.width,canvas.height);g.strokeStyle='#e2bd74';g.lineWidth=2;g.beginPath();for(let i=0;i<samples.length;i++){const x=i/samples.length*canvas.width,y=55-samples[i]*50;i?g.lineTo(x,y):g.moveTo(x,y);}g.stroke();}
function wav(samples){const b=new ArrayBuffer(44+samples.length*2),v=new DataView(b);const str=(p,s)=>[...s].forEach((c,i)=>v.setUint8(p+i,c.charCodeAt(0)));str(0,'RIFF');v.setUint32(4,b.byteLength-8,true);str(8,'WAVEfmt ');v.setUint32(16,16,true);v.setUint16(20,1,true);v.setUint16(22,1,true);v.setUint32(24,48000,true);v.setUint32(28,96000,true);v.setUint16(32,2,true);v.setUint16(34,16,true);str(36,'data');v.setUint32(40,samples.length*2,true);samples.forEach((s,i)=>v.setInt16(44+i*2,Math.round(Math.max(-1,Math.min(1,s))*(s<0?32768:32767)),true));return new Blob([b],{type:'audio/wav'});}
$('record').onclick=async()=>{
  busy=true;lock();status('Opening microphone…');
  try{
    document.querySelectorAll('audio').forEach(a=>a.pause());
    if(!navigator.mediaDevices?.getUserMedia)throw Error('Open this studio in Edge or Chrome using the local address.');
    stream=await navigator.mediaDevices.getUserMedia({audio:{deviceId:$('microphone').value?{exact:$('microphone').value}:undefined,channelCount:1,echoCancellation:false,noiseSuppression:false,autoGainControl:false}});
    ctx=new AudioContext({sampleRate:48000});await ctx.resume();await ctx.audioWorklet.addModule('/capture.js');
    source=ctx.createMediaStreamSource(stream);node=new AudioWorkletNode(ctx,'critter-capture');chunks=[];count=0;let peak=0;
    node.port.onmessage=({data})=>{if(!recording)return;data=data.subarray(0,Math.max(0,ctx.sampleRate*120-count));chunks.push(data);count+=data.length;let p=0;for(const x of data)p=Math.max(p,Math.abs(x));peak=Math.max(peak,p);$('level').textContent=peak>=.99?'Clipping detected — try a softer take':`Peak ${p>0?(20*Math.log10(p)).toFixed(0):'−∞'} dB`;wave(data);if(count>=ctx.sampleRate*120)stop();};
    source.connect(node);node.connect(ctx.destination);recording=true;started=performance.now();tick=setInterval(()=>{const s=(performance.now()-started)/1000;$('timer').textContent=`${String(Math.floor(s/60)).padStart(2,'0')}:${(s%60).toFixed(1).padStart(4,'0')}`;},100);
    stream.getAudioTracks()[0].onended=()=>{if(recording)stop();};status('Recording… Give your critter a voice.');await devices();
  }catch(e){recording=false;cleanup();await ctx?.close().catch(()=>{});status(`Microphone could not start: ${e.message}. Check browser and Windows microphone permissions.`);}finally{busy=false;lock();}
};
async function stop(){if(!recording)return;recording=false;busy=true;lock();const rate=ctx.sampleRate;cleanup();await ctx.close();try{if(count<rate*.1)throw Error('That take was too short. Try at least a tenth of a second.');let samples=new Float32Array(count),offset=0;for(const chunk of chunks){samples.set(chunk,offset);offset+=chunk.length;}if(rate!==48000){const offline=new OfflineAudioContext(1,Math.ceil(count*48000/rate),48000),buf=offline.createBuffer(1,count,rate);buf.copyToChannel(samples,0);const s=offline.createBufferSource();s.buffer=buf;s.connect(offline.destination);s.start();samples=(await offline.startRendering()).getChannelData(0);}draft=wav(samples);draftURL=URL.createObjectURL(draft);$('preview').src=draftURL;$('download').href=draftURL;$('download').download=`${$('character').value}-${$('emotion').value}.wav`;$('draft').hidden=false;status('Take ready. Listen, then save or retry.');}catch(e){status(e.message);}finally{chunks=[];busy=false;lock();}}
$('stop').onclick=stop;
$('voiceImport').onchange=async()=>{
  const file=$('voiceImport').files[0];if(!file)return;busy=true;lock();let decoder;
  try{
    if(file.size>32000000)throw Error('Voice file exceeds 32 MB.');
    decoder=new AudioContext({sampleRate:48000});const input=await decoder.decodeAudioData(await file.arrayBuffer());
    if(input.duration<.1||input.duration>120)throw Error('Import between 0.1 seconds and two minutes.');
    const offline=new OfflineAudioContext(1,Math.ceil(input.duration*48000),48000),source=offline.createBufferSource();source.buffer=input;source.connect(offline.destination);source.start();
    const mono=await offline.startRendering();draft=wav(mono.getChannelData(0));draftURL=URL.createObjectURL(draft);$('preview').src=draftURL;$('download').href=draftURL;$('download').download=`${$('character').value}-${$('emotion').value}.wav`;$('draft').hidden=false;
    status('Imported and converted to mono 48 kHz WAV. Listen, then save to this character and emotion.');
  }catch(e){status('Import failed: '+e.message);}finally{await decoder?.close().catch(()=>{});$('voiceImport').value='';busy=false;lock();}
};
function discard(){draft=null;if(draftURL)URL.revokeObjectURL(draftURL);draftURL=null;$('preview').removeAttribute('src');$('preview').load();$('draft').hidden=true;$('timer').textContent='00:00.0';$('level').textContent='Microphone off';lock();}
$('discard').onclick=()=>{discard();status('Ready for another take.');};
$('save').onclick=async()=>{busy=true;lock();$('save').disabled=true;$('discard').disabled=true;try{const r=await fetch(`/api/takes?character=${encodeURIComponent($('character').value)}&emotion=${encodeURIComponent($('emotion').value)}`,{method:'POST',headers:{'Content-Type':'audio/wav','X-Studio-Token':library.token},body:draft});const result=await r.json();if(!r.ok)throw Error(result.error);discard();status('Saved to the project. Ready for another take.');await refresh();}catch(e){status(`Save failed: ${e.message}. Your unsaved take is still here; retry or download it.`);}finally{busy=false;$('save').disabled=false;$('discard').disabled=false;lock();}};
$('character').onchange=render;$('emotion').onchange=render;$('refresh').onclick=()=>refresh().catch(e=>status(e.message));
window.addEventListener('beforeunload',e=>{if(recording||draft||busy||editDirty){e.preventDefault();e.returnValue='';}});
document.addEventListener('play',e=>{if(e.target.tagName==='AUDIO')document.querySelectorAll('audio').forEach(a=>{if(a!==e.target)a.pause();});},true);
refresh().catch(e=>{status(e.message);$('record').disabled=true;});

function formatBytes(n){return n>=1000000?(n/1000000).toFixed(2)+' MB':(n/1000).toFixed(1)+' KB';}
const effectIds=['trimStart','trimEnd','pitch','gate','crush','bits','hold','editRate','autoTrim','rumble','normalize','preset','editName'];
function options(){return {start:Number($('trimStart').value),end:Number($('trimEnd').value),pitch:Number($('pitch').value),gate:Number($('gate').value),crush:Number($('crush').value),bits:Number($('bits').value),hold:Number($('hold').value),rate:Number($('editRate').value),trim:$('autoTrim').checked,rumble:$('rumble').checked,normalize:$('normalize').checked};}
function applyOptions(s){for(const k of ['pitch','gate','crush','bits','hold'])$(k).value=s[k];$('editRate').value=s.rate;$('autoTrim').checked=s.trim;$('rumble').checked=s.rumble;$('normalize').checked=s.normalize;readouts();}
function readouts(){for(const k of ['pitch','gate','crush','bits','hold'])$(k+'Value').textContent=$(k).value;}
function invalidate(){readouts();editDirty=true;editBlob=null;$('editSave').disabled=true;$('editAudio').pause();$('editAudio').hidden=true;$('editDownload').hidden=true;if(editURL)URL.revokeObjectURL(editURL);editURL=null;$('editStatus').textContent='Settings changed. Preview to hear and save this version.';}
function editorBusy(value){busy=value;for(const id of [...effectIds,'editPreview','editClose','saveVoice','applyVoice'])$(id).disabled=value;$('editSave').disabled=value||!editBlob;lock();}
async function openEditor(t){
  editing=t;editorBusy(true);$('editor').hidden=false;$('editTitle').textContent=`${title(t.emotion)} · ${t.label||'Original recording'}`;$('editStatus').textContent='Loading source…';$('editor').scrollIntoView({behavior:'smooth',block:'start'});
  try{
    document.querySelectorAll('audio').forEach(a=>a.pause());
    // Reopen a version's source and recipe instead of baking the effect twice.
    const base=t.source?library.takes.find(x=>x.character===t.character&&x.emotion===t.emotion&&x.name===t.source):null;
    editing=base||t;const r=await fetch(editing.url);if(!r.ok)throw Error('Could not load source WAV.');editData=decodeWav(new Uint8Array(await r.arrayBuffer()));
    $('editOriginal').src=editing.url;const duration=editData.samples.length/editData.rate;
    const voice=library.presets?.[t.character];const saved=base&&t.settings?t.settings:{...defaults,rate:48000,...voice?.settings};
    $('trimStart').value=saved.start;$('trimEnd').value=saved.end||duration;$('trimStart').max=duration;$('trimEnd').max=duration;
    $('editName').value=t.label?`${t.label} variation`.slice(0,60):'Clean version';$('preset').value='clean';applyOptions(saved);editBlob=null;editDirty=false;
    $('editAudio').hidden=true;$('editDownload').hidden=true;$('editStatus').textContent='Adjust the controls, then preview. Nothing is saved until you choose Save edited version.';
  }catch(e){editing=null;editData=null;$('editor').hidden=true;status(e.message);}finally{editorBusy(false);}
}
for(const id of effectIds.filter(id=>!['preset','editName'].includes(id)))$(id).oninput=invalidate;
$('editName').oninput=()=>{editDirty=true;};
$('preset').onchange=()=>{const p=$('preset').value,s={...defaults,rate:Number($('editRate').value)};if(p==='retro')Object.assign(s,{crush:45,bits:8,hold:5});if(p==='arcade')Object.assign(s,{crush:85,bits:6,hold:9});if(p==='tiny')Object.assign(s,{pitch:5,crush:20,bits:8,hold:3});applyOptions(s);$('editName').value=$('preset').selectedOptions[0].textContent;invalidate();};
$('editPreview').onclick=async()=>{
  editorBusy(true);$('editStatus').textContent='Rendering preview…';
  try{
    await new Promise(r=>requestAnimationFrame(()=>setTimeout(r,0)));
    const result=processAudio(editData.samples,editData.rate,options());
    if(editURL)URL.revokeObjectURL(editURL);editBlob=new Blob([encodeWav(result.samples,result.rate)],{type:'audio/wav'});editURL=URL.createObjectURL(editBlob);
    $('editAudio').src=editURL;$('editAudio').hidden=false;$('editDownload').href=editURL;$('editDownload').download=`${editing.character}-${editing.emotion}-edited.wav`;$('editDownload').hidden=false;
    $('editStatus').textContent=`Preview: ${(result.samples.length/result.rate).toFixed(2)} seconds · ${formatBytes(editBlob.size)} · mono ${result.rate/1000} kHz. Original: ${formatBytes(editing.bytes)}. Preview uses no project disk space.`;
    editDirty=true;await $('editAudio').play().catch(()=>{});
  }catch(e){editBlob=null;$('editStatus').textContent=e.message;}finally{editorBusy(false);}
};
$('editSave').onclick=async()=>{
  editorBusy(true);
  try{
    const r=await fetch('/api/versions',{method:'POST',headers:{'Content-Type':'application/json','X-Studio-Token':library.token},body:JSON.stringify({character:editing.character,emotion:editing.emotion,source:editing.name,label:$('editName').value,settings:options()})});
    const result=await r.json();if(!r.ok)throw Error(result.error);
    editDirty=false;$('editStatus').textContent=result.existing?'This exact audio is already saved. No duplicate file was created.':'Edited version saved. Your source recording is unchanged.';await refresh();
  }catch(e){$('editStatus').textContent=`Save failed: ${e.message}. Your preview is still available to download.`;}finally{editorBusy(false);}
};
$('editClose').onclick=()=>{if(editDirty&&!confirm('Close without saving these changes? Your original and previously saved versions are safe.'))return;editing=null;editData=null;editBlob=null;editDirty=false;$('editAudio').pause();$('editOriginal').pause();if(editURL)URL.revokeObjectURL(editURL);editURL=null;$('editor').hidden=true;lock();};

async function postStudio(endpoint,body){
  const r=await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json','X-Studio-Token':library.token},body:JSON.stringify(body)});
  const result=await r.json();if(!r.ok)throw Error(result.error);return result;
}
$('batchVoice').onclick=async()=>{
  const character=$('character').value;
  busy=true;lock();$('batchStatus').textContent='Loading the saved character voice…';
  try{
    // Refresh before starting so another tab's saved preset or new takes are included.
    await refresh();
    const result=await applyVoiceBatch(character,library.takes,library.presets?.[character],
      body=>postStudio('/api/versions',body),
      p=>{$('batchStatus').textContent=`Applying voice: ${p.done} / ${p.total} originals · ${title(p.take.emotion)}`;});
    $('batchStatus').textContent=`Finished: ${result.created} edited versions saved, ${result.reused} existing versions reused, ${result.failed.length} failed.`;
    if(result.failed.length)$('batchStatus').textContent+=' Retry the batch to try failed takes again. '+result.failed.map(f=>`${f.emotion} (${f.name}): ${f.error}`).join(' ');
    await refresh();
  }catch(e){$('batchStatus').textContent=`Batch stopped: ${e.message}. Any versions already saved are safe; retrying reuses them.`;}
  finally{busy=false;lock();}
};
$('saveVoice').onclick=async()=>{
  if(library.presets?.[editing.character]&&!confirm('Replace this character’s saved voice preset with these effects? Existing takes will not change.'))return;
  editorBusy(true);
  try{await postStudio('/api/preset',{character:editing.character,settings:options()});await refresh();$('editStatus').textContent='Character voice saved. Open another original take to use it, or apply it to an existing edit. Trim points stay specific to each take.';}
  catch(e){$('editStatus').textContent=e.message;}finally{editorBusy(false);}
};
$('applyVoice').onclick=()=>{
  const voice=library.presets?.[editing.character];
  if(!voice){$('editStatus').textContent='No character voice saved yet. Set the effects you like and choose Save as character voice.';return;}
  applyOptions(voice.settings);invalidate();$('editStatus').textContent='Character voice applied. Your start/end trim points are unchanged. Preview, then save a separate edited version.';
};
async function chooseTake(t,clear){
  busy=true;lock();try{await postStudio('/api/select',{character:t.character,emotion:t.emotion,name:t.name,clear});await refresh();status(clear?'Chosen take cleared.':'Chosen take saved for this sound. This selection does not add audio to a game build yet.');}
  catch(e){status(e.message);}finally{busy=false;lock();}
}
async function deleteTake(t){
  const selected=library.selected?.[`${t.character}/${t.emotion}`]===t.name;
  if(!confirm(`Permanently delete ${t.label||'this original recording'} (${title(t.emotion)}, ${t.seconds.toFixed(2)} seconds)?${selected?' This also clears the chosen take for this sound.':''} This cannot be undone.`))return;
  busy=true;lock();try{document.querySelectorAll('audio').forEach(a=>a.pause());await postStudio('/api/delete',{character:t.character,emotion:t.emotion,name:t.name});await refresh();status('Take deleted from the project.');}
  catch(e){status(e.message);}finally{busy=false;lock();}
}
