// Save sequentially so large libraries do not flood the server or hold many WAVs.
export async function applyVoiceBatch(character, takes, preset, save, onProgress=()=>{}) {
  if(!preset?.settings)throw Error('Save a character voice preset first.');
  const originals=takes.filter(t=>t.character===character&&t.kind==='original');
  const voice={...preset.settings,start:0,end:0};
  const result={total:originals.length,created:0,reused:0,failed:[]};
  for(let i=0;i<originals.length;i++){
    const t=originals[i];
    onProgress({done:i,total:originals.length,take:t});
    try{
      const saved=await save({character,emotion:t.emotion,source:t.name,label:'Character voice',settings:{...voice}});
      if(saved.existing)result.reused++;else result.created++;
    }catch(e){result.failed.push({emotion:t.emotion,name:t.name,error:e.message||String(e)});}
    onProgress({done:i+1,total:originals.length,take:t});
  }
  return result;
}
