import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {readFile,writeFile,mkdir,access} from 'node:fs/promises';
import {resolve,dirname,relative} from 'node:path';
import {fileURLToPath} from 'node:url';

// ImageGen drew complete poses. This script only selects intact grid cells,
// registers a clip with ONE scale, and packages review images. It never mattes
// a colour, replaces alpha, warps body parts, or changes animation timing.
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const option=(key,fallback)=>process.argv.find(v=>v.startsWith('--'+key+'='))?.slice(key.length+3)??fallback;
const apply=process.argv.includes('--apply-config');
const require=createRequire(import.meta.url);
let sharp;
try{sharp=require('sharp');}catch{sharp=require(resolve(process.env.USERPROFILE,'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp'));}
const base='assets/images/full-asset-redraw-20261116';
const configFile=resolve(root,base,'config.json');
const out=resolve(root,option('output','docs/qa-godot-native/full-asset-redraw-20261116/actors'));
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const readJson=async path=>JSON.parse((await readFile(path,'utf8')).replace(/^\uFEFF/,''));
const rel=path=>relative(root,path).replaceAll('\\','/');
const exists=async path=>{try{await access(path);return true;}catch{return false;}};
function rectOf(image,predicate){
 let left=image.width,top=image.height,right=-1,bottom=-1,count=0;
 for(let y=0;y<image.height;y++)for(let x=0;x<image.width;x++){
  const index=(y*image.width+x)*4;
  if(!predicate(image.data,index,x,y))continue;
  count++;left=Math.min(left,x);top=Math.min(top,y);right=Math.max(right,x);bottom=Math.max(bottom,y);
 }
 return count?[left,top,right-left+1,bottom-top+1]:null;
}
async function imageData(bytes){const {data,info}=await sharp(bytes).ensureAlpha().raw().toBuffer({resolveWithObject:true});return {data,width:info.width,height:info.height};}
function measure(image){
 const alpha8=rectOf(image,(d,i)=>d[i+3]>=8);
 const alpha128=rectOf(image,(d,i)=>d[i+3]>=128);
 if(!alpha128)return {alpha8,alpha128,empty:true};
 const hat=rectOf(image,(d,i,x,y)=>d[i+3]>=128&&d[i]>120&&d[i]>d[i+1]*2.1&&d[i]>d[i+2]*1.6&&y<alpha128[1]+alpha128[3]*.5);
 let clear=0,partial=0,opaque=0;
 for(let i=3;i<image.data.length;i+=4){const a=image.data[i];if(a===0)clear++;else if(a===255)opaque++;else partial++;}
 const corners=[image.data[3],image.data[(image.width-1)*4+3],image.data[(image.height-1)*image.width*4+3],image.data[(image.width*image.height-1)*4+3]];
 return {alpha8,alpha128,hat,alpha:{clear,partial,opaque},corners,empty:false};
}
const median=values=>{const sorted=[...values].sort((a,b)=>a-b);return sorted[Math.floor(sorted.length/2)];};
function runtimeHatWidth(image){
 const cap=rectOf(image,(d,i,x,y)=>y>=20&&y<126&&d[i+3]>=128&&d[i]>255*.31&&d[i]>d[i+1]*1.4&&d[i]>d[i+2]*1.4);
 return cap?.[2]??0;
}
async function registeredPose(bytes,measurement,scale,masterAnchor,logicalAnchor){
 const crop=measurement.alpha8;
 const width=Math.round(crop[2]*scale),height=Math.round(crop[3]*scale);
 const left=Math.round(logicalAnchor[0]+(crop[0]-masterAnchor[0])*scale),top=Math.round(logicalAnchor[1]+(crop[1]-masterAnchor[1])*scale);
 if(left<0||top<0||left+width>256||top+height>256)return {fits:false,rect:[left,top,width,height]};
 const sampled=await sharp(bytes).extract({left:crop[0],top:crop[1],width:crop[2],height:crop[3]}).resize(width,height,{kernel:'lanczos3'}).png().toBuffer();
 const png=await sharp({create:{width:256,height:256,channels:4,background:{r:0,g:0,b:0,alpha:0}}}).composite([{input:sampled,left,top}]).png().toBuffer();
 return {fits:true,rect:[left,top,width,height],png,image:await imageData(png)};
}
const clipSpecs=[
 {id:'frontwalk',master:'actor-frontwalk-sheet.png',identity:'front',generation:'exec-4973bd1f-cac7-4eb5-a73b-ae8f5a4ed0ed.png'},
 {id:'backwalk',master:'actor-backwalk-sheet-v2.png',identity:'back',pendingMaster:'actor-backwalk-sheet.png'},
 {id:'sidewalk',master:'actor-sidewalk-sheet.png',identity:'side',generation:'exec-984e8da3-cae9-42f1-8663-19fd5182c937.png'},
 {id:'jump',master:'actor-jump-sheet.png',identity:'front',generation:null},
];
const config=await readJson(configFile);
const originalActorDefinition=await readFile(resolve(root,'godot/content/actor-elements.json'));
const definitions=JSON.parse(originalActorDefinition.toString('utf8'));
await mkdir(out,{recursive:true});
const candidateFrames=resolve(root,'.cache/full-actor-redraw-preview');
await mkdir(candidateFrames,{recursive:true});
const updates=new Map(),clips=[],pending=[];
const poses=[];
const sourceAliases=new Map(config.entries.filter(e=>e.id.startsWith('actor-')).flatMap(e=>(e.aliases??[]).map(alias=>[alias,e])));
for(const spec of clipSpecs){
 const reference=await readJson(resolve(root,base,'references',spec.id+'.reference.json'));
 const path=resolve(root,base,'masters',spec.master);
 if(!await exists(path)){
  const pendingPath=resolve(root,base,'masters',spec.pendingMaster??spec.master);
  let reason='A redrawn clip master is not present yet.';
  if(spec.id==='backwalk')reason='Original generated back sheet paints a front berry knot on the back; pending the corrected layered leaf-cape version. No colour-key removal is permitted or needed.';
  pending.push({clip:spec.id,master:rel(pendingPath),reason});continue;
 }
 const bytes=await readFile(path),meta=await sharp(bytes).metadata(),full=await imageData(bytes),fullMeasure=measure(full);
 if(fullMeasure.corners.some(a=>a!==0)||fullMeasure.alpha.clear<full.width*full.height*.4)throw Error(spec.id+': sprite sheet background is not transparently isolated');
 const cells=[];
 for(const cell of reference.cells){
  const left=Math.floor(meta.width*cell.column/reference.columns),right=Math.floor(meta.width*(cell.column+1)/reference.columns);
  const top=Math.floor(meta.height*cell.row/reference.rows),bottom=Math.floor(meta.height*(cell.row+1)/reference.rows);
  const masterRect=[left,top,right-left,bottom-top];
  const frameBytes=await sharp(bytes).extract({left,top,width:right-left,height:bottom-top}).png().toBuffer();
  const image=await imageData(frameBytes),measurement=measure(image);
  if(measurement.empty||!measurement.hat)throw Error(spec.id+': an expected complete pose is missing');
  if(measurement.alpha128[0]===0||measurement.alpha128[1]===0||measurement.alpha128[0]+measurement.alpha128[2]>=image.width||measurement.alpha128[1]+measurement.alpha128[3]>=image.height)throw Error(spec.id+': a pose touches a cell edge');
  cells.push({reference:cell,masterRect,bytes:frameBytes,image,measurement});
 }
 // Uniform scale for the complete clip, not a per-frame alpha-bounds fit.
 // Use the neutral first jump pose; walks share the group's standing envelope.
 const hatTop=median(cells.map(c=>c.measurement.hat[1]));
 const standingBottom=spec.id==='jump'?cells[0].measurement.alpha8[1]+cells[0].measurement.alpha8[3]:Math.max(...cells.map(c=>c.measurement.alpha8[1]+c.measurement.alpha8[3]));
 const masterAnchor=[median(cells.map(c=>c.measurement.hat[0]+c.measurement.hat[2]/2)),standingBottom];
 const scale=216/(standingBottom-hatTop);
 const rows=[];
 for(const cell of cells){
  const target=sourceAliases.get(cell.reference.alias);
  if(!target)throw Error('Reference alias is not mapped to a configured actor source: '+cell.reference.alias);
  const updated={...target,master:rel(path),master_rect:cell.masterRect,generator:'built-in image_gen',generation_id:spec.generation??target.generation_id??null,
   registration:{mode:'scale',scale,master_anchor:masterAnchor,logical_anchor:[128,236]},registration_locked:true,
   review_note:'Complete generated pose; one uniform scale/anchor for the '+spec.id+' clip. Same source SHA groups, fps and runtime clip order are retained.',
   actor_clip:{id:spec.id,slot:cell.reference.slot,reference:base+'/references/'+spec.id+'.reference.json',old_aliases:cell.reference.oldShaGroup}};
  delete updated.cell;delete updated.registration_measurement;
  updates.set(updated.id,updated);
  const crop=cell.measurement.alpha8;
  const width=Math.round(crop[2]*scale),height=Math.round(crop[3]*scale);
  const left=Math.round(128+(crop[0]-masterAnchor[0])*scale),top=Math.round(236+(crop[1]-masterAnchor[1])*scale);
  if(left<0||top<0||left+width>256||top+height>256)throw Error(spec.id+'/'+updated.id+': registered intact pose exceeds its logical canvas');
  const sampled=await sharp(cell.bytes).extract({left:crop[0],top:crop[1],width:crop[2],height:crop[3]}).resize(width,height,{kernel:'lanczos3'}).png().toBuffer();
  const output=await sharp({create:{width:256,height:256,channels:4,background:{r:0,g:0,b:0,alpha:0}}}).composite([{input:sampled,left,top}]).png().toBuffer();
  await writeFile(resolve(candidateFrames,updated.id+'.png'),output);
  rows.push({id:updated.id,alias:cell.reference.alias,oldAliases:cell.reference.oldShaGroup,masterRect:cell.masterRect,logicalCanvas:[256,256],master:cell.measurement,projectedRect:[left,top,width,height],logicalHatWidth:cell.measurement.hat[2]*scale,logicalHatTop:top+(cell.measurement.hat[1]-crop[1])*scale,preview:rel(resolve(candidateFrames,updated.id+'.png'))});
 }
 // New side sheet's first cell is a neutral, feet-together left-facing pose.
 // Reusing it avoids a standing/walking costume or size discontinuity.
 if(spec.id==='sidewalk'){
  const idle=config.entries.find(e=>e.id==='actor-idle-side');
  updates.set(idle.id,{...idle,...Object.fromEntries(['master','master_rect','generation_id','registration','registration_locked'].map(k=>[k,updates.get(rows[0].id)[k]])),
   actor_clip:{id:spec.id,slot:0,semanticReuse:'Neutral left-facing stance from the generated clip first cell; same camera, body and feet.'},review_note:'Shared intact neutral pose with side walk first cell; no body-part compositing.'});
 }
 if(spec.id==='backwalk'){
  const idle=config.entries.find(e=>e.id==='actor-idle-back');
  updates.set(idle.id,{...idle,...Object.fromEntries(['master','master_rect','generation_id','registration','registration_locked'].map(k=>[k,updates.get(rows[0].id)[k]])),
   actor_clip:{id:spec.id,slot:0,semanticReuse:'Neutral feet-together back stance in corrected clip first cell.'},review_note:'Shared intact neutral back pose with corrected back-walk first cell; no body-part compositing.'});
 }
 const frameBuffers=[];
 const actualClip=definitions.skins['luvie.original'].clips[reference.sourceClip];
 const aliasToRow=new Map(rows.flatMap(row=>row.oldAliases.map(alias=>[alias,row])));
 const timeline=[];
 for(const alias of actualClip.frames){
  const row=aliasToRow.get(alias);
  if(!row){
   timeline.push({alias,externalReuse:alias});
   if(spec.id==='backwalk'&&['walk-back-1','walk-back-7'].includes(alias))frameBuffers.push(await sharp(resolve(root,rows[0].preview)).flatten({background:'#dddfc8'}).raw().toBuffer());
   continue;
  }
  timeline.push({alias,id:row.id,slot:rows.indexOf(row)});
  frameBuffers.push(await sharp(resolve(root,row.preview)).flatten({background:'#dddfc8'}).raw().toBuffer());
 }
 if(frameBuffers.length){
  // An animated GIF is a review artifact, never a shipped frame source.
  const joined=Buffer.concat(frameBuffers);
  // GIF uses 10ms ticks. Quantise cumulative time so previews do not drift
  // after a cycle; the shipped engine fps and timeline are never rewritten.
  const delays=frameBuffers.map((_,i)=>10*(Math.round((i+1)*100/actualClip.fps)-Math.round(i*100/actualClip.fps)));
  await sharp(joined,{raw:{width:256,height:256*frameBuffers.length,channels:3,pageHeight:256}}).gif({delay:delays,loop:0}).toFile(resolve(out,spec.id+'.gif'));
 }
 const composites=[];
 for(let i=0;i<rows.length;i++)composites.push({input:await readFile(resolve(root,rows[i].preview)),left:(i%4)*256,top:Math.floor(i/4)*256});
 await sharp({create:{width:1024,height:Math.ceil(rows.length/4)*256,channels:4,background:'#dddfc8'}}).composite(composites).png().toFile(resolve(out,spec.id+'-registered.png'));
 clips.push({id:spec.id,master:rel(path),masterSha256:sha(bytes),masterCanvas:[meta.width,meta.height],grid:[reference.columns,reference.rows],alpha:fullMeasure.alpha,corners:fullMeasure.corners,
  scale,masterAnchor,logicalFoot:[128,236],method:'ONE uniform scale and shared clip anchor, intact grid cells; fractional master grid boundaries are floor-partitioned without resampling.',
  fps:actualClip.fps,loop:actualClip.loop,timeline,frames:rows,visualAcceptance:'Candidate packaging only; actual Godot GPU action review remains required.'});
}
// Existing action clips already have runtime scale/sole overrides. Their new
// PNGs compensate for those existing transforms; normalising them to standing
// height here would shrink them a second time in NativeActorPose.apply().
const actionSpecs=[
 {id:'actor-interact',master:'actor-interact.png',clip:'interact',masterFoot:[648,1168],note:'Manual visible boot-sole registration, excludes skirt/cape; new crouch is more upright than the old pose and needs actual hand/object GPU review.'},
 {id:'actor-salute',master:'actor-salute.png',clip:'complete',masterFoot:[684,1139],note:'Manual visible boot-sole registration, gentle bow.'},
 {id:'actor-sow-1',master:'actor-sow-1.png',clip:'sow',frame:0,masterFoot:[756,1164],note:'Manual boot-sole registration; the separate soil/seed patch is not a body foot.'},
 {id:'actor-sow-5',master:'actor-salute.png',clip:'sow',frame:4,masterFoot:[684,1139],note:'Reuses the complete intact eyes-closed bow, registered to the existing final sow frame foot.'},
];
for(const spec of actionSpecs){
 const file=resolve(root,base,'masters',spec.master);
 if(!await exists(file)){pending.push({pose:spec.id,master:rel(file),reason:'Complete generated pose not available yet.'});continue;}
 const entry=config.entries.find(e=>e.id===spec.id),bytes=await readFile(file),image=await imageData(bytes),m=measure(image);
 const cap=rectOf(image,(d,i,x,y)=>d[i+3]>=128&&d[i]>120&&d[i]>d[i+1]*2.1&&d[i]>d[i+2]*1.6&&y<m.alpha128[1]+m.alpha128[3]*.65);
 let pose=definitions.skins['luvie.original'].pose_overrides[spec.clip];
 if(pose.frames)pose=pose.frames[String(spec.frame)];
 const targetWidth=116/pose.scale;
 let scale=targetWidth/cap[2],preview;
 for(let attempt=0;attempt<6;attempt++){
  preview=await registeredPose(bytes,m,scale,spec.masterFoot,pose.foot);
  if(!preview.fits)throw Error(spec.id+': preserve the actual feet and required head scale, but art leaves logical canvas: '+preview.rect.join(','));
  const measured=runtimeHatWidth(preview.image);
  if(Math.abs(measured-targetWidth)<=.75)break;
  scale*=targetWidth/measured;
 }
 const effectiveHat=runtimeHatWidth(preview.image)*pose.scale;
 if(Math.abs(effectiveHat-116)>1.25)throw Error(spec.id+': runtime anatomical head calibration did not converge');
 const updated={...entry,master:rel(file),registration:{mode:'scale',scale,master_anchor:spec.masterFoot,logical_anchor:pose.foot},registration_locked:true,
  actor_pose:{clip:spec.clip,frame:spec.frame??null,existing_runtime_scale:pose.scale,existing_runtime_foot:pose.foot,target_effective_hat:116},
  review_note:spec.note+' Existing native pose scale and foot definitions are unchanged.'};
 delete updated.master_rect;delete updated.cell;delete updated.registration_measurement;
 updates.set(updated.id,updated);
 await writeFile(resolve(candidateFrames,updated.id+'.png'),preview.png);
 // This contact applies the same pose scale and foot pivot as the real
 // AnimatedSprite3D. It is still a raster review, not a Godot GPU claim.
 const displaySize=Math.round(256*pose.scale),display=await sharp(preview.png).resize(displaySize,displaySize).png().toBuffer();
 const displayLeft=Math.round(128-pose.foot[0]*pose.scale),displayTop=Math.round(236-pose.foot[1]*pose.scale);
 await sharp({create:{width:256,height:256,channels:4,background:'#dddfc8'}}).composite([{input:display,left:displayLeft,top:displayTop}]).png().toFile(resolve(out,spec.id+'-runtime-pose.png'));
 poses.push({id:spec.id,master:rel(file),masterSha256:sha(bytes),sourceAlpha128:m.alpha128,masterFoot:spec.masterFoot,uniformScale:scale,logicalFoot:pose.foot,existingRuntimeScale:pose.scale,
  logicalRect:preview.rect,logicalHatWidth:runtimeHatWidth(preview.image),effectiveHatPixels:effectiveHat,preview:rel(resolve(candidateFrames,updated.id+'.png')),note:spec.note});
}
const ballEntry=config.entries.find(e=>e.id==='actor-ball'),ballFile=resolve(root,base,'masters','actor-ball.png');
if(await exists(ballFile)){
 const bytes=await readFile(ballFile),m=measure(await imageData(bytes)),b=m.alpha8;
 const scale=Math.min(89/b[2],99/b[3]);
 const centre=[b[0]+b[2]/2,b[1]+b[3]/2];
 const updated={...ballEntry,master:rel(ballFile),registration:{mode:'scale',scale,master_anchor:centre,logical_anchor:[44.5,49.5]},registration_locked:true,
  review_note:'Intact red-spotted rolling ball, uniformly fit around the original full-canvas centre. Original roll pixel_size/height and procedural companion UV remain unchanged; GPU checks body/ground clearance.'};
 delete updated.registration_measurement;updates.set(updated.id,updated);
 poses.push({id:updated.id,master:rel(ballFile),masterSha256:sha(bytes),uniformScale:scale,logicalAnchor:[44.5,49.5],method:'Uniform centered fit inside original 89x99 canvas; no oval stretch or painted cast shadow.'});
}
if(apply){
 // Re-read just before writing so concurrent non-actor registrations survive.
 const latest=await readJson(configFile);
 latest.entries=latest.entries.map(entry=>updates.get(entry.id)??entry);
 await writeFile(configFile,JSON.stringify(latest,null,2)+'\n');
}
const afterDefinitions=await readFile(resolve(root,'godot/content/actor-elements.json'));
if(sha(afterDefinitions)!==sha(originalActorDefinition))throw Error('Actor definitions changed during packaging');
const report={date:'2026-11-17',scope:'Mechanical generated clip-cell packaging and candidate animation review, not runtime GPU acceptance.',appliedToConfig:apply,actorDefinitionSha256:sha(originalActorDefinition),actorDefinitionUnchanged:true,
 updatedEntries:[...updates.keys()],pending,clips,poses};
await writeFile(resolve(out,'actor-sheet-review.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({updated:updates.size,clips:clips.map(c=>c.id),pending,report:rel(resolve(out,'actor-sheet-review.json'))}));
