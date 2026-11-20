import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {readFile,writeFile,mkdir,readdir,rename,unlink} from 'node:fs/promises';
import {dirname,resolve,relative,sep,extname} from 'node:path';
import {fileURLToPath} from 'node:url';

// ImageGen supplies the artwork. This tool only registers and packages it; it
// does not threshold alpha, remove a background, blur edges, or invent pixels.
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const option=(key,fallback)=>process.argv.find(v=>v.startsWith('--'+key+'='))?.slice(key.length+3)??fallback;
const has=flag=>process.argv.includes('--'+flag);
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const require=createRequire(import.meta.url);
let sharp;
try{sharp=require(option('sharp','sharp'));}catch{
 sharp=require(resolve(process.env.USERPROFILE??process.env.HOME??'','.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp'));
}
function fail(message){throw Error(message);}
function pathInRoot(value){
 if(typeof value!=='string'||!value)fail('A workspace-relative path is required');
 const path=resolve(root,value.startsWith('res://')?'godot/'+value.slice(6):value);
 const rel=relative(root,path);
 if(rel==='..'||rel.startsWith('..'+sep)||/^[a-z]:/i.test(rel))fail('Path leaves this workspace: '+value);
 return path;
}
const projectPath=path=>relative(root,path).split(sep).join('/');
function resourcePath(path){
 const rel=relative(resolve(root,'godot'),path);
 if(rel==='..'||rel.startsWith('..'+sep)||/^[a-z]:/i.test(rel))fail('Runtime output must stay in godot/: '+path);
 return 'res://'+rel.split(sep).join('/');
}
async function json(path){return JSON.parse((await readFile(path,'utf8')).replace(/^\uFEFF/,''));}
async function optionalJson(path){try{return await json(path);}catch(e){if(e.code==='ENOENT')return null;throw e;}}
async function save(path,value){await mkdir(dirname(path),{recursive:true});await writeFile(path,JSON.stringify(value,null,2)+'\n');}
async function pixels(input){
 const bytes=typeof input==='string'?await readFile(input):input;
 const {data,info}=await sharp(bytes).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 return {bytes,data,width:info.width,height:info.height,channels:info.channels};
}
function bounds(image,threshold=8){
 let x0=image.width,y0=image.height,x1=-1,y1=-1,count=0;
 for(let y=0;y<image.height;y++)for(let x=0;x<image.width;x++){
  if(image.data[(y*image.width+x)*image.channels+3]<threshold)continue;
  count++;x0=Math.min(x0,x);y0=Math.min(y0,y);x1=Math.max(x1,x);y1=Math.max(y1,y);
 }
 return {rect:count?[x0,y0,x1-x0+1,y1-y0+1]:[0,0,0,0],pixels:count};
}
function alphaStats(image){
 const result={clear:0,partial:0,opaque:0};
 for(let i=3;i<image.data.length;i+=image.channels){const a=image.data[i];result[a===0?'clear':a===255?'opaque':'partial']++;}
 return result;
}
function descriptor(image,path){return {path:projectPath(path),sha256:sha(image.bytes),canvas:[image.width,image.height],alpha8:bounds(image,8),alpha128:bounds(image,128),alpha:alphaStats(image)};}
async function sampleMaster(entry,full){
 let region=entry.master_rect;
 if(entry.cell){
  if(region)fail(entry.id+': choose master_rect or cell, not both');
  const cell=entry.cell,origin=pair(cell.origin??[0,0],'cell origin'),gap=pair(cell.gap??[0,0],'cell gap');
  if(![cell.column,cell.row,cell.width,cell.height,...origin,...gap].every(Number.isInteger)||cell.column<0||cell.row<0||cell.width<1||cell.height<1)fail(entry.id+': cell needs integer column,row,width,height');
  region=[origin[0]+cell.column*(cell.width+gap[0]),origin[1]+cell.row*(cell.height+gap[1]),cell.width,cell.height];
 }
 region=rect(region??[0,0,full.width,full.height],entry.id+' master_rect');
 if(region[0]<0||region[1]<0||region[0]+region[2]>full.width||region[1]+region[3]>full.height)fail(entry.id+': master_rect leaves the supplied sheet');
 if(region[0]===0&&region[1]===0&&region[2]===full.width&&region[3]===full.height)return {image:full,region};
 const bytes=await sharp(full.bytes).extract({left:region[0],top:region[1],width:region[2],height:region[3]}).png().toBuffer();
 return {image:await pixels(bytes),region};
}
function pair(value,label){if(!Array.isArray(value)||value.length!==2||!value.every(Number.isFinite))fail(label+' must be [x,y]');return value;}
function rect(value,label){if(!Array.isArray(value)||value.length!==4||!value.every(Number.isInteger)||value[2]<1||value[3]<1)fail(label+' must be integer [x,y,width,height]');return value;}
function mapPoint(point,t){return [t.left+(point[0]-t.crop[0])*t.width/t.crop[2],t.top+(point[1]-t.crop[1])*t.height/t.crop[3]];}
function pointAt(r,anchor){return [r[0]+r[2]*anchor[0],r[1]+r[3]*anchor[1]];}
function makeTransform(entry,original,master,ready){
 const spec=entry.registration??{},mode=spec.mode??'contain';
 if(mode==='shared'){
  const other=ready.get(spec.entry);
  if(!other)fail(entry.id+': shared registration must refer to an earlier exported/configured entry');
  const referenceCanvas=other.master.sample?.canvas??other.master.canvas;
  if(referenceCanvas[0]!==master.width||referenceCanvas[1]!==master.height||other.original.canvas[0]!==original.width||other.original.canvas[1]!==original.height)fail(entry.id+': shared states must have identical sampled master and logical canvases');
  return {...other.transform,crop:[...other.transform.crop],mode,sharedWith:spec.entry};
 }
 const crop=rect(spec.crop??bounds(master,spec.alpha_threshold??8).rect,entry.id+' crop');
 if(crop[0]<0||crop[1]<0||crop[0]+crop[2]>master.width||crop[1]+crop[3]>master.height)fail(entry.id+': crop leaves master canvas');
 let scale,left,top;
 if(mode==='contain'||mode==='height'){
  const target=rect(spec.target??bounds(original,spec.alpha_threshold??8).rect,entry.id+' target');
  const anchor=pair(spec.anchor??[.5,1],entry.id+' anchor');
  if(anchor.some(v=>v<0||v>1))fail(entry.id+': contain anchor must be within 0..1');
  scale=mode==='height'?target[3]/crop[3]:Math.min(target[2]/crop[2],target[3]/crop[3]);
  const masterAnchor=pointAt(crop,anchor),logicalAnchor=pointAt(target,anchor);
  left=logicalAnchor[0]-(masterAnchor[0]-crop[0])*scale;
  top=logicalAnchor[1]-(masterAnchor[1]-crop[1])*scale;
 }else if(mode==='anchors'){
  if(!Array.isArray(spec.points)||spec.points.length<2)fail(entry.id+': at least two paired registration points required');
  const points=spec.points.map(p=>({master:pair(p.master,'master point'),logical:pair(p.logical,'logical point')}));
  const mean=key=>[0,1].map(axis=>points.reduce((sum,p)=>sum+p[key][axis],0)/points.length);
  const m=mean('master'),l=mean('logical');let numerator=0,denominator=0;
  for(const p of points)for(const axis of [0,1]){const d=p.master[axis]-m[axis];numerator+=d*(p.logical[axis]-l[axis]);denominator+=d*d;}
  scale=numerator/denominator;
  left=l[0]+(crop[0]-m[0])*scale;top=l[1]+(crop[1]-m[1])*scale;
 }else if(mode==='scale'){
  scale=spec.scale;
  const m=pair(spec.master_anchor,'master_anchor'),l=pair(spec.logical_anchor,'logical_anchor');
  left=l[0]+(crop[0]-m[0])*scale;top=l[1]+(crop[1]-m[1])*scale;
 }else fail(entry.id+': unsupported registration mode '+mode);
 if(!Number.isFinite(scale)||scale<=0)fail(entry.id+': invalid uniform scale');
 const t={mode,crop,left:Math.round(left),top:Math.round(top),width:Math.max(1,Math.round(crop[2]*scale)),height:Math.max(1,Math.round(crop[3]*scale)),uniformScale:scale,rounding:'nearest logical pixel',sharedWith:null};
 const fit=spec.max_translation_fit??0;
 if(!Number.isFinite(fit)||fit<0||fit>2)fail(entry.id+': max_translation_fit may only be an explicit 0..2 logical pixel allowance');
 if(fit&&t.width<=original.width&&t.height<=original.height){
  const x=Math.min(Math.max(t.left,0),original.width-t.width),y=Math.min(Math.max(t.top,0),original.height-t.height);
  const delta=[x-t.left,y-t.top];
  if(Math.hypot(...delta)<=fit){t.translationFit={delta,maxAllowed:fit,review:'Explicit sub-two-pixel footprint/rounding allowance; source dimensions and alpha are not altered.'};t.left=x;t.top=y;}
 }
 if(mode==='scale'){
  t.anchor={master:spec.master_anchor,logical:spec.logical_anchor,mapped:mapPoint(spec.master_anchor,t)};
  t.anchor.error=Math.hypot(t.anchor.mapped[0]-t.anchor.logical[0],t.anchor.mapped[1]-t.anchor.logical[1]);
 }
 // A one-pixel rounding difference is permitted; deliberate nonuniform fitting
 // is not. Narrow one-pixel stems are still checked in the actual GPU scene.
 if(Math.abs(t.width/crop[2]-t.height/crop[3])>Math.max(1/crop[2],1/crop[3]))fail(entry.id+': unexpected nonuniform registration');
 if(mode==='anchors'){
  t.points=spec.points.map(p=>({...p,mapped:mapPoint(p.master,t)}));
  t.maxPointError=Math.max(...t.points.map(p=>Math.hypot(p.mapped[0]-p.logical[0],p.mapped[1]-p.logical[1])));
  if(t.maxPointError>(spec.max_point_error??1))fail(entry.id+': paired feet/anchors differ by '+t.maxPointError.toFixed(3)+' logical pixels; review the art rather than stretching it');
 }
 return t;
}
async function registry(){
 const result={};
 for(const entry of (await json(pathInRoot('godot/content/visual-assets.json'))).entries)result[entry.id]=entry.resource;
 for(const file of ['prop-elements','actor-elements','surface-elements'])for(const [alias,value]of Object.entries((await json(pathInRoot('godot/content/'+file+'.json'))).resources??{})){
  const resource=typeof value==='object'?value.resource:value;
  if(result[alias]&&result[alias]!==resource)fail('Conflicting registered alias: '+alias);
  result[alias]=resource;
 }
 return result;
}
async function protectedSources(){
 const files={};
 async function visit(folder){
  for(const entry of await readdir(folder,{withFileTypes:true})){
   if(entry.isDirectory()){if(!['.godot','build','tests','assets','web'].includes(entry.name))await visit(resolve(folder,entry.name));}
   else if(['.gd','.gdshader','.tscn','.json','.godot'].includes(extname(entry.name))){
    const path=resolve(folder,entry.name),rel=projectPath(path);
    if(['godot/content/element-theme.json','godot/content/bitmap-redraw.json'].includes(rel))continue;
    files[rel]=sha(await readFile(path));
   }
  }
 }
 await visit(pathInRoot('godot'));
 return Object.fromEntries(Object.entries(files).sort(([a],[b])=>a.localeCompare(b)));
}
function same(a,b){return JSON.stringify(a)===JSON.stringify(b);}
const importParameters={
 'compress/mode':'0','mipmaps/generate':'true','mipmaps/limit':'-1',
 'process/fix_alpha_border':'true','process/premult_alpha':'false',
 'process/size_limit':'0','detect_3d/compress_to':'0',
};
function importText(existing='[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n'){
 let result=existing;
 if(!result.includes('[params]'))result+='\n[params]\n';
 for(const [key,value]of Object.entries(importParameters)){
  const pattern=new RegExp('^'+key.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'=.*$','m');
  if(pattern.test(result))result=result.replace(pattern,key+'='+value);else result+='\n'+key+'='+value;
 }
 return result+'\n';
}
async function existingText(path){try{return await readFile(path,'utf8');}catch(e){if(e.code==='ENOENT')return '';throw e;}}
function validateConfig(config){
 if(config.schema_version!==1||!/^[-a-z0-9]{1,64}$/.test(config.id)||!Array.isArray(config.entries)||!config.entries.length)fail('Config requires schema_version=1, a short id and nonempty entries');
 const ids=new Set(),aliases=new Set(),sources=new Set(),outputs=new Set();
 const outputDir=pathInRoot(config.output_dir),manifestPath=pathInRoot(config.manifest);
 resourcePath(outputDir);
 for(const entry of config.entries){
  if(!/^[-a-z0-9]{1,96}$/.test(entry.id)||ids.has(entry.id))fail('Invalid or duplicate asset id: '+entry.id);ids.add(entry.id);
  entry.aliases??=[];entry.bindings??=[];entry.source_paths??=[];
  if(!Array.isArray(entry.aliases)||!Array.isArray(entry.bindings)||!Array.isArray(entry.source_paths)||!entry.aliases.length&&!entry.bindings.length&&!entry.source_paths.length)fail(entry.id+': aliases, source_paths or explicit direct-load bindings required');
  for(const alias of entry.aliases){if(typeof alias!=='string'||aliases.has(alias))fail('Duplicate/invalid alias: '+alias);aliases.add(alias);}
  for(const path of entry.source_paths){
   if(typeof path!=='string'||!path.startsWith('res://assets/images/')||sources.has(path))fail(entry.id+': source_paths must be unique full res://assets/images/ paths');
   sources.add(path);
  }
  const original=pathInRoot(entry.original),master=pathInRoot(entry.master),output=resolve(outputDir,entry.file??entry.id+'.png');
  if(!output.startsWith(outputDir+sep)||extname(output)!=='.png'||outputs.has(output)||output===original||output===master)fail(entry.id+': output must be a distinct PNG inside output_dir');
  outputs.add(output);entry._paths={original,master,output};
  for(const binding of entry.bindings)if(typeof binding.path!=='string')fail(entry.id+': direct binding requires a source path');
 }
 return {outputDir,manifestPath};
}
async function activate(files){
 // Both candidates are staged before the first runtime file is changed. A
 // failed second replace restores the first; no permissive partial theme is
 // deliberately retained. Runtime readers still validate their own batch.
 const staged=[];
 for(const [path,value]of files){
  let original=null;try{original=await readFile(path);}catch(e){if(e.code!=='ENOENT')throw e;}
  await mkdir(dirname(path),{recursive:true});const temporary=path+'.redraw-pending';
  await writeFile(temporary,JSON.stringify(value,null,2)+'\n');staged.push({path,temporary,original});
 }
 const replaced=[];
 try{for(const item of staged){await rename(item.temporary,item.path);replaced.push(item);}}
 catch(error){
  for(const item of replaced.reverse())if(item.original)await writeFile(item.path,item.original);else await unlink(item.path).catch(()=>{});
  for(const item of staged)await unlink(item.temporary).catch(()=>{});
  throw error;
 }
}

if(has('help')||!option('config','')){
 console.log('node tools/godot-migration/export-full-asset-redraw.mjs --config=<workspace JSON> [--only=id,...] [--apply-theme] [--check] [--expect-applied]\nDefault export writes lossless sibling PNGs, a provenance manifest and theme.proposed.json; the playable theme changes only with --apply-theme. Read tools/godot-migration/full-asset-redraw-pipeline.md.');
 if(!has('help'))process.exitCode=1;
}else{
 const configFile=pathInRoot(option('config','')),config=await json(configFile);
 const configSha=sha(Buffer.from(JSON.stringify(config)));
 const {manifestPath}=validateConfig(config);
 const proposedPath=pathInRoot(config.proposed_theme??projectPath(resolve(dirname(manifestPath),'theme.proposed.json')));
 const proposedSourcePath=pathInRoot(config.proposed_source_map??projectPath(resolve(dirname(manifestPath),'bitmap-redraw.proposed.json')));
 const themeFile=pathInRoot(config.theme_path??'godot/content/element-theme.json');
 const sourceMapFile=pathInRoot(config.source_map_path??'godot/content/bitmap-redraw.json');
 const currentTheme=await json(themeFile),registered=await registry(),before=await protectedSources();
 const currentSourceMap=await optionalJson(sourceMapFile)??{schema_version:1,source_overrides:{}};
 if(currentTheme.schema_version!==1||!currentTheme.resource_overrides)fail('Invalid existing theme');
 if(currentSourceMap.schema_version!==1||!currentSourceMap.source_overrides)fail('Invalid existing source map');
 const previous=await optionalJson(manifestPath);
 const selected=new Set(option('only','').split(',').filter(Boolean));
 for(const id of selected)if(!config.entries.some(e=>e.id===id))fail('Unknown selected id: '+id);
 if(previous&&!same(previous.protectedSources,before))fail('Rule/geometry/actor/UI source differs from the recorded baseline; inspect the change instead of silently rebasing this art manifest');
 const pending=[];const ready=new Map(previous?.entries?.map(e=>[e.id,e])??[]);
 const proposed=structuredClone(currentTheme);
 const proposedSource=structuredClone(currentSourceMap);
 const preserve=previous?.preservedOverrides??Object.fromEntries(Object.entries(currentTheme.resource_overrides).filter(([alias])=>!config.entries.some(e=>e.aliases.includes(alias))));
 const preservedSources=previous?.preservedSourceOverrides??Object.fromEntries(Object.entries(currentSourceMap.source_overrides).filter(([source])=>!config.entries.some(e=>e.source_paths.includes(source))));
 for(const [alias,path]of Object.entries(preserve))if(currentTheme.resource_overrides[alias]!==path)fail('Existing unmodified theme override changed: '+alias);
 for(const [source,path]of Object.entries(preservedSources))if(currentSourceMap.source_overrides[source]!==path)fail('Existing unmodified source override changed: '+source);
 for(const entry of config.entries){
  if(selected.size&&!selected.has(entry.id))continue;
  for(const alias of entry.aliases){if(!registered[alias])fail(entry.id+': unknown runtime alias '+alias);}
  const original=await pixels(entry._paths.original),fullMaster=await pixels(entry._paths.master);
  if(entry.source_sha256&&entry.source_sha256!==sha(original.bytes))fail(entry.id+': original differs from the audited source hash');
  const sampled=await sampleMaster(entry,fullMaster),master=sampled.image;
  if(!alphaStats(master).clear)fail(entry.id+': master has no true transparent pixels; regenerate with alpha');
  for(const alias of entry.aliases){
   const baseline=await pixels(pathInRoot(registered[alias]));
   if(baseline.width!==original.width||baseline.height!==original.height)fail(entry.id+': original logical canvas does not match alias '+alias);
   if(sha(baseline.bytes)!==sha(original.bytes))fail(entry.id+': declared original is not the registered source for '+alias);
  }
  for(const source of entry.source_paths){
   const baseline=await pixels(pathInRoot(source));
   if(sha(baseline.bytes)!==sha(original.bytes))fail(entry.id+': source_paths use different bytes/canvas; create a separate export for '+source);
  }
  if(has('check')){
   const record=ready.get(entry.id);if(!record)fail(entry.id+': no exported manifest entry');
   if(!same(record.config,JSON.parse(JSON.stringify(entry,(key,value)=>key==='_paths'?undefined:value))))fail(entry.id+': config differs from exported registration');
   const result=await pixels(entry._paths.output);
   if(sha(original.bytes)!==record.original.sha256||sha(fullMaster.bytes)!==record.master.sha256||sha(result.bytes)!==record.output.sha256)fail(entry.id+': original, master or output provenance differs');
   if(record.master.sample&&!same(record.master.sample.rect,sampled.region))fail(entry.id+': sheet frame selection differs');
   if(!same([result.width,result.height],[original.width,original.height]))fail(entry.id+': logical canvas changed');
   if(!same(bounds(result,8),record.output.alpha8)||!same(bounds(result,128),record.output.alpha128))fail(entry.id+': alpha measurements differ');
   if(!alphaStats(result).partial)fail(entry.id+': output has no fractional alpha');
   const imports=await readFile(entry._paths.output+'.import','utf8');
   for(const [key,value]of Object.entries(importParameters))if(!imports.split(/\r?\n/).includes(key+'='+value))fail(entry.id+': missing import setting '+key);
   const res=resourcePath(entry._paths.output);
   for(const alias of entry.aliases)if(has('expect-applied')&&currentTheme.resource_overrides[alias]!==res)fail(entry.id+': replacement is not active for '+alias);
   for(const source of entry.source_paths)if(has('expect-applied')&&currentSourceMap.source_overrides[source]!==res)fail(entry.id+': replacement is not active for direct source '+source);
   for(const binding of entry.bindings)if(has('expect-applied')&&!(await readFile(pathInRoot(binding.path),'utf8')).includes(binding.contains??res))fail(entry.id+': direct-load consumer is not bound: '+binding.path);
   pending.push(record);
  }else{
   let existing=false;
   try{await readFile(entry._paths.output);existing=true;}catch(error){if(error.code!=='ENOENT')throw error;}
   if(existing&&!ready.has(entry.id))fail(entry.id+': output already exists without ownership in this manifest; use a new sibling path');
   const transform=makeTransform(entry,original,master,ready);
   const {crop,left,top,width,height}=transform;
   if(left<0||top<0||left+width>original.width||top+height>original.height)fail(entry.id+': registered art leaves the logical canvas; correct the anchors, do not clip');
   const visible=bounds(master,8).rect;
   if(visible[0]<crop[0]||visible[1]<crop[1]||visible[0]+visible[2]>crop[0]+crop[2]||visible[1]+visible[3]>crop[1]+crop[3])fail(entry.id+': registration crop cuts visible art; explicitly redraw/reframe the master');
   const resized=await sharp(master.bytes).ensureAlpha().extract({left:crop[0],top:crop[1],width:crop[2],height:crop[3]}).resize(width,height,{fit:'fill',kernel:'lanczos3'}).png().toBuffer();
   let bytes=await sharp({create:{width:original.width,height:original.height,channels:4,background:{r:0,g:0,b:0,alpha:0}}}).composite([{input:resized,left,top}]).png({compressionLevel:9}).toBuffer();
   if(entry.alpha_mask){
    const mask=entry.alpha_mask,samples=mask.antialias_scale??4;
    if(!['inside','outside'].includes(mask.mode)||!Number.isInteger(samples)||samples<2||samples>8||!Array.isArray(mask.polygons)||!mask.polygons.length)fail(entry.id+': invalid explicit alpha_mask');
    const paths=mask.polygons.map(polygon=>{
     if(!Array.isArray(polygon)||polygon.length<3)fail(entry.id+': alpha mask polygon needs at least three points');
     for(const p of polygon){pair(p,'alpha mask point');if(p[0]<0||p[1]<0||p[0]>original.width||p[1]>original.height)fail(entry.id+': alpha mask point leaves logical canvas');}
     return '<path d="M'+polygon.map(p=>p.join(',')).join(' L')+' Z" fill="'+(mask.mode==='inside'?'white':'black')+'"/>';
    }).join('');
    const w=original.width,h=original.height;
    const svg='<svg xmlns="http://www.w3.org/2000/svg" width="'+w*samples+'" height="'+h*samples+'" viewBox="0 0 '+w+' '+h+'"><defs><mask id="registered-holes" maskUnits="userSpaceOnUse" x="0" y="0" width="'+w+'" height="'+h+'"><rect width="'+w+'" height="'+h+'" fill="'+(mask.mode==='inside'?'black':'white')+'"/>'+paths+'</mask></defs><rect width="'+w+'" height="'+h+'" fill="white" mask="url(#registered-holes)"/></svg>';
    const alpha=await sharp(Buffer.from(svg)).resize(w,h,{kernel:'lanczos3'}).png().toBuffer();
    bytes=await sharp(bytes).composite([{input:alpha,blend:'dest-in'}]).png({compressionLevel:9}).toBuffer();
   }
   const output=await pixels(bytes);
   if(!alphaStats(output).partial)fail(entry.id+': output has no antialiased alpha; review the master/scale');
   const record={id:entry.id,aliases:entry.aliases,bindings:entry.bindings,source_paths:entry.source_paths,config:JSON.parse(JSON.stringify(entry,(key,value)=>key==='_paths'?undefined:value)),original:descriptor(original,entry._paths.original),master:{...descriptor(fullMaster,entry._paths.master),sample:{rect:sampled.region,canvas:[master.width,master.height],alpha8:bounds(master,8),alpha128:bounds(master,128)}},transform,output:{...descriptor(output,entry._paths.output),mipmaps:true},visualAcceptance:'Pending actual GPU review; canvas and anchors alone do not certify the artwork or complete physical footprint.'};
   pending.push({...record,_bytes:bytes});ready.set(entry.id,record);
  }
 }
 for(const record of ready.values()){
  const path=resourcePath(pathInRoot(record.output.path));
  for(const alias of record.aliases)proposed.resource_overrides[alias]=path;
  for(const source of record.source_paths??[])proposedSource.source_overrides[source]=path;
 }
 proposed.id=config.id;
 if(!same(before,await protectedSources()))fail('Protected production source changed during packaging');
 if(has('check')){
  const savedProposal=await json(proposedPath);
  const savedSourceProposal=await json(proposedSourcePath);
  for(const record of pending)for(const alias of record.aliases)if(savedProposal.resource_overrides[alias]!==resourcePath(pathInRoot(record.output.path)))fail('Proposed theme does not cover '+alias);
  for(const record of pending)for(const source of record.source_paths??[])if(savedSourceProposal.source_overrides[source]!==resourcePath(pathInRoot(record.output.path)))fail('Proposed source map does not cover '+source);
  for(const [alias,path]of Object.entries(preserve))if(savedProposal.resource_overrides[alias]!==path)fail('Proposed theme drops an earlier override: '+alias);
  for(const [source,path]of Object.entries(preservedSources))if(savedSourceProposal.source_overrides[source]!==path)fail('Proposed source map drops an earlier override: '+source);
  console.log(JSON.stringify({passed:true,checked:pending.length,scope:'Hashes, logical canvas, alpha, imports, alias/source coverage, prior overrides and protected source identity; GPU review remains separate.',applied:pending.every(r=>r.aliases.every(a=>currentTheme.resource_overrides[a]===resourcePath(pathInRoot(r.output.path)))&&(r.source_paths??[]).every(s=>currentSourceMap.source_overrides[s]===resourcePath(pathInRoot(r.output.path))))}));
 }else{
  for(const record of pending){await mkdir(dirname(pathInRoot(record.output.path)),{recursive:true});await writeFile(pathInRoot(record.output.path),record._bytes);await writeFile(pathInRoot(record.output.path)+'.import',importText(await existingText(pathInRoot(record.output.path)+'.import')));delete record._bytes;ready.set(record.id,record);}
  const entries=config.entries.map(e=>ready.get(e.id)).filter(Boolean);
  const manifest={schema_version:1,id:config.id,config:projectPath(configFile),configSha256:configSha,sampling:'sharp '+sharp.versions.sharp+' / libvips '+sharp.versions.vips+'; alpha-aware Lanczos3; uniform registration',preservedOverrides:preserve,preservedSourceOverrides:preservedSources,protectedSources:before,scope:'Mechanical packaging of supplied redraws. No rule, collision, layout, actor motion, saved-state or depth changes. Complete silhouette/footprint and actual GPU acceptance remain required.',entries};
  await save(manifestPath,manifest);await save(proposedPath,proposed);await save(proposedSourcePath,proposedSource);
  if(has('apply-theme'))await activate([[themeFile,proposed],[sourceMapFile,proposedSource]]);
  console.log(JSON.stringify({exported:pending.length,manifest:projectPath(manifestPath),proposedTheme:projectPath(proposedPath),proposedSources:projectPath(proposedSourcePath),applied:has('apply-theme'),preservedOverrides:Object.keys(preserve).length,preservedSourceOverrides:Object.keys(preservedSources).length}));
 }
}
