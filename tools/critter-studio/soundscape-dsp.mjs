export function encodePCM(channels,rate){
 const length=channels[0].length,n=channels.length;if(n<1||n>2||channels.some(c=>c.length!==length))throw Error('Use one or two matching audio channels.');
 const b=new ArrayBuffer(44+length*n*2),v=new DataView(b),str=(p,s)=>[...s].forEach((c,i)=>v.setUint8(p+i,c.charCodeAt(0)));
 str(0,'RIFF');v.setUint32(4,b.byteLength-8,true);str(8,'WAVEfmt ');v.setUint32(16,16,true);v.setUint16(20,1,true);v.setUint16(22,n,true);v.setUint32(24,rate,true);v.setUint32(28,rate*n*2,true);v.setUint16(32,n*2,true);v.setUint16(34,16,true);str(36,'data');v.setUint32(40,length*n*2,true);
 for(let i=0;i<length;i++)for(let c=0;c<n;c++){const x=Math.max(-1,Math.min(1,channels[c][i]));v.setInt16(44+(i*n+c)*2,Math.round(x*(x<0?32768:32767)),true);}return b;
}
export function processSound(channels,rate,s){
 const duration=channels[0].length/rate;
 const bounds={start:[0,duration],end:[.1,duration],pitch:[-12,12],gain:[-24,12],bits:[4,16],crush:[0,100],fade:[0,5]};
 for(const [k,[lo,hi]]of Object.entries(bounds))if(!Number.isFinite(s[k])||s[k]<lo||s[k]>hi)throw Error(`Invalid ${k}.`);
 if(s.end-s.start<.1)throw Error('Keep at least 0.1 seconds.');
 const begin=Math.round(s.start*rate),end=Math.round(s.end*rate),step=2**(s.pitch/12),length=Math.floor((end-begin)/step);
 if(length/rate>600||length/rate<.1)throw Error('Edited audio must be between 0.1 seconds and 10 minutes.');
 let input=channels.map(c=>c.slice(begin,end));
 if(s.mono&&input.length>1){const mono=new Float32Array(input[0].length);for(let i=0;i<mono.length;i++)mono[i]=(input[0][i]+input[1][i])*.5;input=[mono];}
 const output=input.map(c=>{const out=new Float32Array(length);let prev=0,hp=0,envelope=0,g=1,held=0;const levels=2**(s.bits-1);
  for(let i=0;i<length;i++){const p=i*step,j=Math.floor(p),f=p-j;let x=(c[j]||0)*(1-f)+(c[j+1]||0)*f;
   hp=.99*(hp+x-prev);prev=x;if(s.clean){x=hp;envelope=Math.max(Math.abs(x),envelope*.9996);const target=Math.min(1,(envelope/.004)**2);g+=(target-g)*(target>g?.08:.003);x*=g;}
   if(i%4===0)held=Math.round(x*levels)/levels;x=x*(1-s.crush/100)+held*s.crush/100;out[i]=x*10**(s.gain/20);
  }return out;
 });
 let peak=0;for(const c of output)for(const x of c)peak=Math.max(peak,Math.abs(x));const norm=s.normalize&&peak>.00001?Math.min(8,.89/peak):1;
 const fade=Math.min(Math.round(s.fade*rate),Math.floor(length/2));let clipped=0;
 for(const c of output)for(let i=0;i<c.length;i++){let x=c[i]*norm;if(fade)x*=Math.min(1,i/fade,(c.length-1-i)/fade);if(Math.abs(x)>1)clipped++;c[i]=Math.max(-1,Math.min(1,x));}
 return {channels:output,rate,clipped};
}
