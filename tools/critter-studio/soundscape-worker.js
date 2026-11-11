import {processSound,encodePCM} from './soundscape-dsp.mjs';
self.onmessage=({data})=>{try{const result=processSound(data.channels,data.rate,data.settings);const wav=encodePCM(result.channels,result.rate);self.postMessage({wav,clipped:result.clipped},[wav]);}catch(e){self.postMessage({error:e.message});}};
