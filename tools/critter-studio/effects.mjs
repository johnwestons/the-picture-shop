// Shared, deterministic processing for browser audition and server-side saves.
export const defaults={start:0,end:0,trim:true,gate:-48,rumble:true,normalize:true,pitch:0,bits:8,crush:0,hold:4,rate:24000};
export function settings(input,duration){
  const s={...defaults,...input};
  for(const [key,min,max] of [['start',0,duration],['end',0,duration],['gate',-80,-20],['pitch',-12,12],['bits',4,16],['crush',0,100],['hold',1,24]]){
    if(typeof s[key]!=='number'||!Number.isFinite(s[key])||s[key]<min||s[key]>max)throw Error(`Invalid ${key}.`);
  }
  for(const key of ['trim','rumble','normalize'])if(typeof s[key]!=='boolean')throw Error(`Invalid ${key}.`);
  if(![24000,48000].includes(s.rate))throw Error('Choose 24 or 48 kHz.');
  s.end=s.end||duration;
  if(s.end-s.start<.1)throw Error('Keep at least 0.1 seconds.');
  s.bits=Math.round(s.bits);s.hold=Math.round(s.hold);
  return Object.fromEntries(Object.keys(defaults).map(k=>[k,s[k]]));
}
export function processAudio(input,rate,options){
  const s=settings(options,input.length/rate);
  let data=input.slice(Math.round(s.start*rate),Math.round(s.end*rate));
  // DC/rumble filter, and a soft envelope-based gate (not spectral denoising).
  let previous=0,high=0,envelope=0,gain=1;const threshold=10**(s.gate/20),release=Math.exp(-1/(rate*.06));
  for(let i=0;i<data.length;i++){
    const x=data[i];high=.99*(high+x-previous);previous=x;
    let y=s.rumble?high:x;
    envelope=Math.max(Math.abs(y),envelope*release);
    const target=Math.min(1,(envelope/threshold)**2);gain+=(target-gain)*(target>gain?.08:.003);
    data[i]=y*gain;
  }
  if(s.trim){
    let first=0,last=data.length-1;const cutoff=Math.max(.003,threshold);
    while(first<last&&Math.abs(data[first])<cutoff)first++;
    while(last>first&&Math.abs(data[last])<cutoff)last--;
    if(last-first>rate*.03)data=data.slice(Math.max(0,first-Math.round(rate*.02)),Math.min(data.length,last+Math.round(rate*.05)));
  }
  if(s.normalize){let peak=0;for(const x of data)peak=Math.max(peak,Math.abs(x));const scale=peak>.0001?Math.min(8,.84/peak):1;for(let i=0;i<data.length;i++)data[i]*=scale;}
  // Pitch is classic resampling: a higher pitch is also faster/shorter.
  const step=2**(s.pitch/12),length=Math.max(Math.round(rate*.1),Math.floor(data.length/step));
  if(length/rate>120)throw Error('Processed take exceeds two minutes. Trim it or raise the pitch.');
  const pitched=new Float32Array(length);
  for(let i=0;i<length;i++){const p=i*step,k=Math.floor(p),f=p-k;pitched[i]=(data[k]||0)*(1-f)+(data[k+1]||0)*f;}
  const levels=2**(s.bits-1),mix=s.crush/100;let held=0;
  for(let i=0;i<pitched.length;i++){if(i%s.hold===0)held=Math.round(pitched[i]*levels)/levels;pitched[i]=pitched[i]*(1-mix)+held*mix;}
  // Windowed-sinc low-pass resampling avoids aliasing when exporting at 24 kHz.
  const ratio=rate/s.rate,out=new Float32Array(Math.max(Math.round(s.rate*.1),Math.floor(pitched.length/ratio)));
  const cutoff=Math.min(1,s.rate/rate)*.9;
  for(let i=0;i<out.length;i++){
    const p=i*ratio,center=Math.floor(p);let sum=0,weight=0;
    for(let k=center-16;k<=center+16;k++){const d=k-p;if(Math.abs(d)>16)continue;const sinc=Math.abs(d)<1e-8?cutoff:Math.sin(Math.PI*d*cutoff)/(Math.PI*d);const w=sinc*(.5+.5*Math.cos(Math.PI*d/16));sum+=(pitched[k]||0)*w;weight+=w;}
    out[i]=sum/weight;
  }
  const fade=Math.min(Math.round(s.rate*.005),Math.floor(out.length/2));
  for(let i=0;i<out.length;i++){const g=Math.min(1,i/fade,(out.length-1-i)/fade);out[i]=Math.max(-.98,Math.min(.98,out[i]*g));}
  return {samples:out,rate:s.rate,settings:s};
}
export function encodeWav(samples,rate){
  const b=new ArrayBuffer(44+samples.length*2),v=new DataView(b);
  const str=(p,s)=>[...s].forEach((c,i)=>v.setUint8(p+i,c.charCodeAt(0)));
  str(0,'RIFF');v.setUint32(4,b.byteLength-8,true);str(8,'WAVEfmt ');v.setUint32(16,16,true);v.setUint16(20,1,true);v.setUint16(22,1,true);v.setUint32(24,rate,true);v.setUint32(28,rate*2,true);v.setUint16(32,2,true);v.setUint16(34,16,true);str(36,'data');v.setUint32(40,samples.length*2,true);
  for(let i=0;i<samples.length;i++)v.setInt16(44+i*2,Math.round(Math.max(-1,Math.min(1,samples[i]))*(samples[i]<0?32768:32767)),true);
  return b;
}
export function decodeWav(bytes){
  const v=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);let rate=0,samples;
  for(let p=12;p+8<=bytes.length;){const tag=String.fromCharCode(...bytes.subarray(p,p+4)),size=v.getUint32(p+4,true);if(tag==='fmt ')rate=v.getUint32(p+12,true);if(tag==='data'){samples=new Float32Array(size/2);for(let i=0;i<samples.length;i++)samples[i]=v.getInt16(p+8+i*2,true)/32768;}p+=8+size+(size%2);}
  if(!samples||!rate)throw Error('No audio samples.');return {samples,rate};
}
