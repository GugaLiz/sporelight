import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {dirname,join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const require=createRequire(import.meta.url);
let sharp;try{sharp=require('sharp');}catch{sharp=require(join(process.env.USERPROFILE,'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp'));}
const output=join(root,'assets/images/full-asset-redraw-20261116/references');
await mkdir(output,{recursive:true});
const manifest=JSON.parse(await readFile(join(root,'godot/content/visual-assets.json'),'utf8'));
const actors=JSON.parse(await readFile(join(root,'godot/content/actor-elements.json'),'utf8'));
const clips=actors.skins['luvie.original'].clips;
const entries=new Map(manifest.entries.map(e=>[e.id,e]));
const sourceFor=new Map(),groups=new Map();
for(const alias of new Set(Object.values(clips).flatMap(clip=>clip.frames))){
 const source=entries.get(alias);if(!source)continue;
 const path='godot/'+source.resource.replace(/^res:\/\//,'');const bytes=await readFile(join(root,path));
 const sha256=createHash('sha256').update(bytes).digest('hex');
 const image=await sharp(bytes).metadata();
 sourceFor.set(alias,{alias,path,bytes,sha256,canvas:[image.width,image.height]});
 if(!groups.has(sha256))groups.set(sha256,[]);groups.get(sha256).push(alias);
}
const specs=[
 {id:'frontwalk',clip:'walk_front',columns:4,rows:2,aliases:['walk-1','walk-7','walk-8','walk-9','walk-10','walk-11','walk-12']},
 {id:'backwalk',clip:'walk_back',columns:3,rows:2,aliases:['walk-back-2','walk-back-3','walk-back-4','walk-back-8','walk-back-9','walk-back-10'],externalReuse:['idle-back']},
 {id:'sidewalk',clip:'walk_left',columns:4,rows:2,aliases:['walk-side-1','walk-side-2','walk-side-3','walk-side-4','walk-side-8','walk-side-9','walk-side-10'],alsoUsedBy:['walk_right']},
 {id:'jump',clip:'jump',columns:3,rows:2,aliases:['jump-1','jump-3','jump-4','jump-5','jump-6']}
];
const results=[];
for(const spec of specs){
 const cells=[],byHash=new Map(),sheetWidth=spec.columns*256,sheetHeight=spec.rows*256;
 const sheetPixels=Buffer.alloc(sheetWidth*sheetHeight*4);
 for(const[slot,alias]of spec.aliases.entries()){
  const source=sourceFor.get(alias);if(source.canvas[0]!==256||source.canvas[1]!==256)throw Error('Reference canvas changed: '+alias);
  const column=slot%spec.columns,row=Math.floor(slot/spec.columns);
  // Packaging only: copy the complete RGBA canvas into a same-size cell.
  // No bounding-box fitting, matting, repaint, label or pose alteration.
  const pixels=await sharp(source.bytes).ensureAlpha().raw().toBuffer();
  for(let y=0;y<256;y++)pixels.copy(sheetPixels,((row*256+y)*sheetWidth+column*256)*4,y*256*4,(y+1)*256*4);
  cells.push({slot,row,column,cellRect:[column*256,row*256,256,256],alias,source:source.path,sourceSha256:source.sha256,oldShaGroup:groups.get(source.sha256),logicalCanvas:[256,256],defaultFoot:[128,236]});
  byHash.set(source.sha256,slot);
 }
 const file=spec.id+'.reference.png';
 await sharp(sheetPixels,{raw:{width:sheetWidth,height:sheetHeight,channels:4}}).png().toFile(join(output,file));
 const savedPixels=await sharp(join(output,file)).ensureAlpha().raw().toBuffer();
 if(!savedPixels.equals(sheetPixels))throw Error('Reference packaging changed RGBA pixels: '+spec.id);
 const external=(spec.externalReuse??[]).map(alias=>({alias,source:sourceFor.get(alias).path,sourceSha256:sourceFor.get(alias).sha256,oldShaGroup:groups.get(sourceFor.get(alias).sha256)}));
 const timeline=clips[spec.clip].frames.map((alias,position)=>{
  const source=sourceFor.get(alias),slot=byHash.get(source.sha256);
  const reuse=external.find(e=>e.sourceSha256===source.sha256);
  if(slot===undefined&&!reuse)throw Error('Missing reference frame: '+alias);
  return {position,oldAlias:alias,oldSha256:source.sha256,...(slot===undefined?{externalReuse:reuse.alias}:{cell:slot})};
 });
 const bytes=await readFile(join(output,file));
 const record={id:spec.id,file,sha256:createHash('sha256').update(bytes).digest('hex'),rgbaPixelsUnchanged:true,sourceClip:spec.clip,alsoUsedBy:spec.alsoUsedBy??[],columns:spec.columns,rows:spec.rows,cellSize:[256,256],sheetSize:[spec.columns*256,spec.rows*256],cellOrder:'row-major, first appearances in the actual clip; no painted indices',emptyCells:Array.from({length:spec.columns*spec.rows},(_,i)=>i).filter(i=>i>=cells.length),fps:clips[spec.clip].fps,loop:clips[spec.clip].loop,cells,externalReuse:external,timeline,registration:{sourceDefaultFoot:[128,236],identityReference:'exec-db868f3e-8786-42ea-95d7-00eab19364c1.png (new front idle master; supplied by parent)',policy:'One common body/hat scale and canvas registration for the whole generated clip. Do not fit each frame by alpha bounds or equalize total height. Preserve native per-clip timing and poses.'}};
 await writeFile(join(output,spec.id+'.reference.json'),JSON.stringify(record,null,2)+'\n');results.push(record);
}
await writeFile(join(output,'actor-reference-index.json'),JSON.stringify({version:1,date:'2026-11-16',method:'Alpha-preserving assembly of unchanged complete 256x256 source canvases; no text drawn into tiles.',scope:'Four animation reference sheets, not generated replacement art. Source aliases are the original source identity, regardless of a future bitmap theme.',sheets:results.map(({cells,timeline,...row})=>({...row,cellCount:cells.length,timelineLength:timeline.length}))},null,2)+'\n');
console.log(JSON.stringify(results.map(r=>({id:r.id,cells:r.cells.length,size:r.sheetSize,sourceFrames:r.timeline.length,external:r.externalReuse.map(x=>x.alias)}))));
