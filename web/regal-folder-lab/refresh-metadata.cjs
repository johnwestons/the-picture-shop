const fs=require('node:fs'),crypto=require('node:crypto');
const path='dist/source.json',meta=JSON.parse(fs.readFileSync(path));
meta.baselineSha256??=meta.sha256;
meta.path='dist/folder.lua';meta.label='Balance test 02';meta.experimental=true;
meta.sha256=crypto.createHash('sha256').update(fs.readFileSync('dist/folder.lua')).digest('hex');
meta.runtime='Fengari Web 0.1.4 (Lua 5.3); experimental test-page rules';
fs.writeFileSync(path,JSON.stringify(meta,null,2)+'\n');
