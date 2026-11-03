#!/usr/bin/env node
// Read-only native presentation timing. No input, launch, install, property,
// SurfaceFlinger counter reset, or profiling-enable commands are issued.
const cp=require('node:child_process');
const fs=require('node:fs');
const path=require('node:path');
const repo=path.resolve(__dirname,'..');
const adb=process.env.ADB || path.join(repo,'output/mobile/tooling/android-sdk/platform-tools/adb.exe');
const serial=process.env.ANDROID_SERIAL || 'R5CY92V6L6B';
const pkg=process.env.PICTURE_SHOP_ANDROID_PACKAGE || 'com.thepictureshop.game';
const output=process.env.PICTURE_SHOP_ANDROID_FRAME_OUTPUT || path.join(repo,'output/mobile/town-device-tests');
function run(args){
 const result=cp.spawnSync(adb,['-s',serial,...args],{encoding:'utf8',windowsHide:true,timeout:15000,maxBuffer:4*1024*1024});
 if(result.error)throw result.error;
 if(result.status!==0)throw Error(args.join(' ')+': '+result.stderr);
 return result.stdout;
}
function quote(value){return "'"+value.replace(/'/g,"'\\''")+"'";}
function candidates(){
 return run(['shell','dumpsys','SurfaceFlinger','--list']).trim().split(/\r?\n/)
  .filter(name=>name.includes(pkg)&&name.includes('SurfaceView')&&!name.includes('Background for'))
  // Android 17 --list emits RequestedLayerState metadata; --latency expects
  // Layer.getName(), including its #sequence suffix, without that wrapper.
  .map(name=>name.replace(/^RequestedLayerState\{/,'').replace(/ parentId=.*$/,''))
  .sort((a,b)=>Number(b.includes('(BLAST)'))-Number(a.includes('(BLAST)')));
}
function parse(raw){
 const lines=raw.trim().split(/\r?\n/);const period=Number(lines.shift());const rows=[];
 for(const line of lines){
  const cells=line.trim().split(/\s+/);if(cells.length!==3||!cells.every(x=>/^\d+$/.test(x)))continue;
  const actual=BigInt(cells[1]);if(actual<=0n||actual>=9223372036854775807n)continue;
  rows.push({desired_ns:cells[0],actual_ns:cells[1],ready_ns:cells[2]});
 }
 return {refresh_period_ns:period,rows};
}
function sample(layer){return parse(run(['shell','dumpsys','SurfaceFlinger','--latency',quote(layer)]));}
function select(){
 const options=candidates().map(name=>({name,...sample(name)}));
 options.sort((a,b)=>b.rows.length-a.rows.length);
 if(!options[0]||!options[0].rows.length)throw Error('No live native SurfaceView presentation records; do not substitute Java gfxinfo.');
 return options[0];
}
function focus(){
 const line=run(['shell','dumpsys','window']).split(/\r?\n/).find(s=>s.includes('mCurrentFocus'))||'';
 if(!line.includes(pkg))throw Error('Game is not focused: '+line);
 return line.trim();
}
function percentile(values,p){return values[Math.min(values.length-1,Math.ceil(values.length*p)-1)]??null;}
function summarize(intervals){
 const sorted=[...intervals].sort((a,b)=>a-b);const total=sorted.reduce((s,v)=>s+v,0);
 return {intervals:sorted.length,presented_fps:total>0?sorted.length*1000/total:null,
  mean_ms:sorted.length?total/sorted.length:null,p50_ms:percentile(sorted,.5),p95_ms:percentile(sorted,.95),p99_ms:percentile(sorted,.99),max_ms:sorted.at(-1)??null,
  intervals_above_16_67ms:sorted.filter(x=>x>1000/60).length,
  intervals_above_17_17ms:sorted.filter(x=>x>1000/60+.5).length,
  intervals_above_33_33ms:sorted.filter(x=>x>1000/30).length};
}
async function capture(label,seconds){
 if(!/^[a-z0-9-]+$/.test(label))throw Error('Use a simple scene-specific label.');
 if(!Number.isFinite(seconds)||seconds<2||seconds>60)throw Error('Duration must be 2–60 seconds.');
 fs.mkdirSync(output,{recursive:true});
 const beforeFocus=focus(),pid=run(['shell','pidof',pkg]).trim();
 const selected=select();let previous=BigInt(selected.rows.at(-1).actual_ns);
 const first=previous,rows=[],intervals=[],polls=[];let gaps=0;
 const started=Date.now(),stop=started+seconds*1000;
 while(Date.now()<stop){
  await new Promise(resolve=>setTimeout(resolve,250));
  const at=Date.now();const current=sample(selected.name);
  const unique=new Map(current.rows.map(row=>[row.actual_ns,row]));
  const newer=[...unique.values()].filter(row=>BigInt(row.actual_ns)>previous)
    .sort((a,b)=>BigInt(a.actual_ns)<BigInt(b.actual_ns)?-1:1);
  let continuous=unique.has(previous.toString());
  if(newer.length&&!continuous){gaps++;}
  for(const row of newer){
   const now=BigInt(row.actual_ns);
   if(continuous)intervals.push(Number(now-previous)/1e6);
   rows.push(row);previous=now;continuous=true;
  }
  polls.push({elapsed_ms:Date.now()-started,query_ms:Date.now()-at,refresh_period_ns:current.refresh_period_ns,new_frames:newer.length});
 }
 const afterFocus=focus(),afterPid=run(['shell','pidof',pkg]).trim();
 if(afterPid!==pid)throw Error('Game process changed during capture; result is not a continuous gameplay sample.');
 const report={label,serial,package:pkg,pid,layer:selected.name,started_at:new Date(started).toISOString(),
  android:run(['shell','getprop','ro.build.version.release']).trim(),model:run(['shell','getprop','ro.product.model']).trim(),
  display_size:run(['shell','wm','size']).trim(),window_seconds:(Date.now()-started)/1000,
  observed_present_span_ms:Number(previous-first)/1e6,frame_records:rows.length,ring_overrun_gaps:gaps,
  initial_refresh_period_ns:selected.refresh_period_ns,focus_before:beforeFocus,focus_after:afterFocus,
  measurement:'SurfaceFlinger native SurfaceView actual-present-fence timestamp intervals',
  note:'Real displayed-buffer intervals, not CPU/GPU execution time. 250ms read-only polling merges the 127-record history. Scene health and scenario are verified by the operator; no UI input is sent. Gaps invalidate complete-window claims.',
  source:'https://android.googlesource.com/platform/frameworks/native/+/refs/heads/main/services/surfaceflinger/FrameTracker.cpp',
  summary:summarize(intervals),polls,frames:rows};
 fs.writeFileSync(path.join(output,label+'-surfaceflinger.json'),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify({file:path.join(output,label+'-surfaceflinger.json'),label,layer:report.layer,ring_overrun_gaps:gaps,...report.summary},null,2));
}
async function main(){
 const command=process.argv[2];
 if(command==='inspect'){
  console.log(JSON.stringify({serial,focus:focus(),layers:candidates().map(name=>{const s=sample(name);return {name,refresh_period_ns:s.refresh_period_ns,valid_records:s.rows.length};})},null,2));
 }else if(command==='capture')await capture(process.argv[3],Number(process.argv[4]||10));
 else throw Error('Usage: node tools/android_frame_probe.cjs inspect | capture <scene-label> [seconds]');
}
if(require.main===module)main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
module.exports={parse,summarize};
