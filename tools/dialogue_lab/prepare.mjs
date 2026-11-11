import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {validateWav} from '../critter-studio/server.mjs';
import crypto from 'node:crypto';
const here=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(here,'../..');
const stage=path.join(root,'output/dialogue-lab');
const state=JSON.parse(fs.readFileSync(path.join(root,'assets/audio/voices/studio.json'),'utf8'));
const emotions=['greeting','neutral','happy','curious','agreement','disagreement','surprised','annoyed','thanks','worried','sad','goodbye'];
const characters=[
 {id:'rabbit-worker',name:'Player Rabbit',source:'assets/generated/characters/rabbit-worker/idle.png'},
 {id:'grandpa',name:'Grandpa',source:'assets/generated/story-intro/grandpa-seated-v1.png',static:true},
 {id:'cat-worker',name:'Radio Cat',source:'assets/generated/characters/cat-worker/idle.png'},
 {id:'tinker-fox-worker',name:'Tinker Fox',source:'assets/generated/characters/tinker-fox-worker/idle.png'},
 {id:'ferret-engineer-worker',name:'Ferret Engineer',source:'assets/generated/characters/ferret-engineer-worker/idle.png'},
 {id:'medic-fox-worker',name:'Medic Fox',source:'assets/generated/characters/medic-fox-worker/idle.png'},
 {id:'mechanic-raccoon',name:'Raccoon Mechanic',source:'assets/source/warehouse-expansion-v1/mechanic-raccoon/idle.png'},
 {id:'business-dragon',name:'Business Dragon',source:'assets/generated/characters/business-dragon/idle.png'},
 {id:'lizard-press-technician',name:'Lizard Press Technician',source:'assets/generated/technician-motion-v2/lizard-press-technician/idle.png'},
 {id:'field-mouse-technician',name:'Field Mouse Technician',source:'assets/generated/technician-motion-v2/field-mouse-technician/idle.png'},
 {id:'business-fox',name:'Business Fox',source:'assets/generated/characters/business-fox/idle.png'},
 {id:'business-cat',name:'Business Cat',source:'assets/generated/characters/business-cat/idle.png'},
 {id:'tan-cat',name:'Tan Cat',source:'assets/generated/characters/tan-cat/idle.png'},
 {id:'green-blazer-cat',name:'Green Blazer Cat',source:'assets/generated/characters/green-blazer-cat/idle.png'},
 {id:'blue-coaler-cat',name:'Blue Coaler Cat',source:'assets/generated/characters/blue-coaler-cat/idle.png'},
];
const voiceNames={'cat-worker':'Radio Cat','mechanic-raccoon':'Raccoon Mechanic','business-dragon':'Business Dragon','medic-fox-worker':'Medic Fox'};
const lua=s=>'"'+s.replaceAll('\\','/').replaceAll('"','\\"')+'"';
const voices=Object.create(null);
// Validate and stage every explicitly selected profile, including any future
// individual voice profiles. Missing Tinker Fox takes remain a valid silent route.
for(const [key,name] of Object.entries(state.selected||{})){
 const [profile,emotion,...extra]=key.split('/');
 if(extra.length||!/^[-a-z0-9]+$/.test(profile)||!emotions.includes(emotion)||!/^(take|edit)-[\w-]+\.wav$/.test(name))throw Error(`Invalid chosen voice entry: ${key}`);
 const source=path.join(root,'assets/audio/voices',profile,emotion,name),data=fs.readFileSync(source),seconds=validateWav(data,[24000,48000]);
 (voices[profile]||={})[emotion]={name,data,seconds,file:`${profile}-${emotion}.wav`};
}
for(const emotion of emotions){if(!voices['cat-worker']?.[emotion])throw Error(`Choose a Radio Cat ${emotion} take in the recording studio first.`)}
fs.mkdirSync(path.join(stage,'characters'),{recursive:true});
for(const name of ['main.lua','conf.lua','dialogue.lua','smoke.lua'])fs.copyFileSync(path.join(here,name),path.join(stage,name));
fs.copyFileSync(path.join(root,'src/speech_bubble.lua'),path.join(stage,'speech_bubble.lua'));
fs.copyFileSync(path.join(root,'src/dialogue_profile.lua'),path.join(stage,'dialogue_profile.lua'));
fs.writeFileSync(path.join(stage,'syntax_checks.lua'),'return {'+['src/sound.lua','src/soundscape.lua','src/jukebox.lua','src/commute/audio.lua','src/dialogue_profile.lua','src/dialogue_voices.lua','src/dialogue_presentation.lua','src/employee_speech.lua','src/employee_renderer.lua','src/runtime/simulation.lua','src/story_intro.lua'].map(p=>lua(path.join(root,p))).join(',')+'}');
for(const name of ['dialogue_presentation','dialogue_voices','soundscape'])fs.copyFileSync(path.join(root,'src',name+'.lua'),path.join(stage,name+'.lua'));
fs.copyFileSync(path.join(root,'assets/generated/characters/rabbit-worker/idle.png'),path.join(stage,'player.png'));
for(const item of characters){
 const sprite=`characters/${item.id}.png`;fs.copyFileSync(path.join(root,item.source),path.join(stage,sprite));item.sprite=sprite;
}
for(const [profile,entries]of Object.entries(voices))for(const entry of Object.values(entries))fs.writeFileSync(path.join(stage,entry.file),entry.data);
const voiceLua=Object.entries(voices).map(([profile,entries])=>`[${lua(profile)}]={`+Object.entries(entries).map(([emotion,entry])=>`[${lua(emotion)}]={file=${lua(entry.file)},source=${lua(entry.name)}}`).join(',')+'}').join(',');
const catClips=Object.entries(voices['cat-worker']).map(([emotion,entry])=>`[${lua(emotion)}]={file=${lua(entry.file)},source=${lua(entry.name)}}`).join(',');
const characterLua=characters.map(item=>`{id=${lua(item.id)},name=${lua(item.name)},sprite=${lua(item.sprite)},static=${item.static===true}}`).join(',');
const namesLua=Object.entries(voiceNames).map(([profile,name])=>`[${lua(profile)}]=${lua(name)}`).join(',');
fs.writeFileSync(path.join(stage,'chosen.lua'),`return {profilePath=${lua(path.join(root,'src/dialogue_profile.lua'))},report=${lua(path.join(stage,'smoke-report.txt'))},voices={${voiceLua}},voiceNames={${namesLua}},characters={${characterLua}},clips={${catClips}}}`);
// Publish only explicitly chosen voice clips, never the recording history.
const destination=path.join(root,'assets/audio/dialogue');fs.mkdirSync(destination,{recursive:true});const voiceMap=Object.create(null),files=[];
for(const [key,name]of Object.entries(state.selected||{})){
 const [character,emotion,...extra]=key.split('/');
 if(extra.length||!/^[-a-z0-9]+$/.test(character)||!emotions.includes(emotion)||!/^(take|edit)-[\w-]+\.wav$/.test(name))throw Error('Invalid chosen voice entry.');
 const data=fs.readFileSync(path.join(root,'assets/audio/voices',character,emotion,name));validateWav(data,[24000,48000]);
 const hash=crypto.createHash('sha256').update(data).digest('hex'),rel=`assets/audio/dialogue/${hash}.wav`;
 fs.writeFileSync(path.join(root,rel),data);if(!files.includes(rel))files.push(rel);(voiceMap[character]||={})[emotion]=rel;
}
const manifestLua='return {'+Object.entries(voiceMap).map(([character,entries])=>`[${lua(character)}]= {`+Object.entries(entries).map(([emotion,rel])=>`[${lua(emotion)}]=${lua(rel)}`).join(',')+'}').join(',')+'}\n';
fs.writeFileSync(path.join(destination,'manifest.lua'),manifestLua);
fs.writeFileSync(path.join(destination,'manifest.json'),JSON.stringify({files,luaSha256:crypto.createHash('sha256').update(manifestLua).digest('hex')},null,2));
const profileCount=Object.keys(voices).length,takeCount=Object.values(voices).reduce((sum,entries)=>sum+Object.keys(entries).length,0);
console.log(`Prepared ${characters.length} character previews and ${takeCount} chosen takes across ${profileCount} voice profiles. ${stage}`);
