import {readFile,writeFile,readdir,copyFile,mkdir,access} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createRequire} from 'node:module';
const root=process.cwd(),require=createRequire(import.meta.url);
const sharp=require(resolve(process.env.USERPROFILE,'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp'));
const base='assets/images/full-asset-redraw-20261116/',configPath=resolve(root,base+'config.json');
const config=JSON.parse((await readFile(configPath,'utf8')).replace(/^\uFEFF/,''));
const jobs=[];
try{jobs.push(...JSON.parse((await readFile(resolve(root,base+'generated-jobs.json'),'utf8')).replace(/^\uFEFF/,'')).jobs.map(j=>({...j,_record:base+'generated-jobs.json#'+j.id})));}catch{}
try{for(const file of await readdir(resolve(root,base+'jobs')))if(file.endsWith('.json'))jobs.push({...JSON.parse(await readFile(resolve(root,base+'jobs',file),'utf8')),_record:base+'jobs/'+file});}catch{}
const jobMap=new Map(jobs.filter(j=>!j.id.startsWith('actor')).map(j=>[j.id,j]));
if(jobMap.has('bug-v2'))jobMap.set('bug',jobMap.get('bug-v2'));
const props=JSON.parse(await readFile(resolve(root,'godot/content/prop-elements.json'),'utf8'));
async function image(file){const{data,info}=await sharp(file).ensureAlpha().raw().toBuffer({resolveWithObject:true});return{data,...info};}
function bounds(im,threshold=8){let a=im.width,b=im.height,c=-1,d=-1;for(let y=0;y<im.height;y++)for(let x=0;x<im.width;x++)if(im.data[(y*im.width+x)*4+3]>=threshold){a=Math.min(a,x);b=Math.min(b,y);c=Math.max(c,x);d=Math.max(d,y);}return[a,b,c-a+1,d-b+1];}
function foot(im,b){let lo=im.width,hi=-1;const from=b[1]+b[3]-Math.max(2,Math.round(b[3]*.05));for(let y=from;y<b[1]+b[3];y++)for(let x=b[0];x<b[0]+b[2];x++)if(im.data[(y*im.width+x)*4+3]>=128){lo=Math.min(lo,x);hi=Math.max(hi,x);}return[(lo+hi)*.5,b[1]+b[3]-.5];}
const existing=new Set();for(const e of config.entries){if(e.id.startsWith('actor'))continue;try{await access(resolve(root,e.master));existing.add(e.id);}catch{}if(jobMap.has(e.id)){const j=jobMap.get(e.id);e.generation_id=j.generation_id;e.prompt_record=j._record;if(j.master)e.master=j.master;}}
// These are the same original drawings at different logical canvases. Reuse
// the already redrawn appearance rather than generating a second identity.
const arch=config.entries.find(e=>e.id==='gallery-arch');
if(arch){arch.master='godot/assets/images/scene-redraw-20261116/arch.png';arch.registration={mode:'scale',scale:1,crop:[0,0,256,256],master_anchor:[0,0],logical_anchor:[0,0]};arch.generation_id='exec-75b57e9e-fafa-47f3-bd9f-ac2960440c42.png';arch.reuse_from='assets/images/scene-redraw-20261116/manifest.json#arch';existing.add(arch.id);}
const lily=config.entries.find(e=>e.id==='gallery-lily');if(lily){lily.master=base+'masters/lotus-pool.png';lily.registration={mode:'contain',anchor:[.5,1]};lily.reuse_from=base+'config.json#lotus-pool';existing.add(lily.id);}
const fresh=new Set(['glow-flower','lotus-pool','small-pebbles','violet-crystal','bush','crystal','lilypad','rock','stairs','stone','bug','light','vine']);
const notes=[];
for(const e of config.entries){
 if(!e.id.startsWith('actor')&&existing.has(e.id)&&e.registration?.mode==='height'&&!fresh.has(e.id)&&!['light-tower','flower-gate-frame','flower-gate-seal'].includes(e.id)){
  e.registration={mode:'contain',anchor:[.5,1]};
  e.review_note='UI cutout uniformly contained in original visible bounds; same logical canvas and actual UI crops require GPU review.';
 }
 if(e.id.startsWith('actor')||!fresh.has(e.id)||!existing.has(e.id)||e.registration_locked)continue;
 const orig=await image(resolve(root,'godot',e.original.slice(6))),master=await image(resolve(root,e.master)),ob=bounds(orig),mb=bounds(master);
 // Soft water/hovering sprites and texture sampling sources are boxed without
 // inventing hard feet. Their existing logical sample coordinates stay fixed.
 if(['lotus-pool','crystal','lilypad','stairs','stone','bug','light','vine'].includes(e.id)){
  e.registration={mode:'contain',anchor:[.5,1]};
  e.review_note='Uniform containment in the original visible bounds; logical canvas/UV sample coordinates unchanged. GPU appearance still needs review.';
  notes.push({id:e.id,mode:'contain',oldBounds:ob,masterBounds:mb});continue;
 }
 const row=props.scenery.source_feet[e.id],mf=foot(master,mb),of=row?[(row[2]+row[3])*.5,row[4]+.5]:foot(orig,ob);
 const desired=ob[3]/mb[3];let scale=desired;
 for(const [space,distance] of [[of[0],mf[0]-mb[0]],[orig.width-of[0],mb[0]+mb[2]-mf[0]],[of[1],mf[1]-mb[1]],[orig.height-of[1],mb[1]+mb[3]-mf[1]]])if(distance>0)scale=Math.min(scale,space/distance);
 e.registration={mode:'scale',scale,master_anchor:mf,logical_anchor:of,max_translation_fit:1};
 e.registration_measurement={source:{canvas:[orig.width,orig.height],alpha8:ob,foot:of},master:{canvas:[master.width,master.height],alpha8:mb,foot:mf},heightRatio:scale/desired,candidate:true};
 e.review_note='Registered to original declared foot using one scale; size ratio is explicit and pending GPU review. No collision or support edits.';
 notes.push({id:e.id,mode:'scale',heightRatio:scale/desired,foot:of});
}
// New tower's opening contours differ slightly from the old crop masks. These
// reviewed inner polygons exclude masonry and remove all of the light membrane.
const windows=[[[87,235],[91,224],[99,213],[106,207],[115,217],[123,234],[124,311],[89,297]],[[149,236],[153,222],[160,211],[164,209],[175,220],[181,237],[181,295],[149,310]]];
for(const id of ['flower-gate-frame','flower-gate-seal']){const e=config.entries.find(e=>e.id===id);e.alpha_mask.polygons=windows;e.review_note='Two window polygons reviewed on the newly registered tower; common transform and AA split retain stone pillars when the seal fades.';}
const plantIds=['map-plant-bloom','map-plant-bud','gallery-cave-bloom','map-plant-dormant','map-plant-pond-bloom'];
const plantEntries=config.entries.filter(e=>plantIds.includes(e.id));
if(plantEntries.every(e=>existing.has(e.id))){
 const sizes=[],boxes=[];for(const e of plantEntries){const im=await image(resolve(root,e.master));sizes.push([im.width,im.height]);boxes.push(bounds(im));}
 if(!sizes.every(s=>s[0]===sizes[0][0]&&s[1]===sizes[0][1]))throw Error('Map state masters must retain a common canvas before shared registration');
 const x=Math.min(...boxes.map(b=>b[0])),y=Math.min(...boxes.map(b=>b[1]));
 const crop=[x,y,Math.max(...boxes.map(b=>b[0]+b[2]))-x,Math.max(...boxes.map(b=>b[1]+b[3]))-y];
 for(const e of plantEntries){
  e.registration=e.id==='map-plant-bloom'?{mode:'contain',anchor:[.5,1],crop}:{mode:'shared',entry:'map-plant-bloom'};
  e.registration_locked=true;e.state_group='chapter-map-plant';
  e.review_note='Edited states share the same master canvas and one union crop/transform; the foreground stone ring and root stay fixed when changing map state.';
 }
}
await writeFile(configPath,JSON.stringify(config,null,2)+'\n');
await mkdir(resolve(root,'docs/qa-godot-native/full-asset-redraw-20261116'),{recursive:true});
await writeFile(resolve(root,'docs/qa-godot-native/full-asset-redraw-20261116/nonactor-registration-progress.json'),JSON.stringify({notes,ready:[...existing],pending:config.entries.filter(e=>!e.id.startsWith('actor')&&!existing.has(e.id)).map(e=>e.id)},null,2)+'\n');
console.log(JSON.stringify({registered:notes.length,ready:existing.size,pending:config.entries.filter(e=>!e.id.startsWith('actor')&&!existing.has(e.id)).map(e=>e.id)}));
