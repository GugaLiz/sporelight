import {readFile,writeFile,mkdir,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';

// This audit compares the frozen consumer/provenance inventory with shipped
// resolution and generated output provenance. It is not a visual-quality test.
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const option=(key,fallback)=>process.argv.find(v=>v.startsWith('--'+key+'='))?.slice(key.length+3)??fallback;
const batch='full-asset-redraw-20261116';
const folder=join(root,'docs/qa-godot-native',batch);
const assetFolder=join(root,'assets/images',batch);
const candidate=process.argv.includes('--candidate');
const allowPartial=process.argv.includes('--allow-partial');
const output=resolve(root,option('output','docs/qa-godot-native/'+batch+'/coverage.json'));
const read=async p=>JSON.parse((await readFile(p,'utf8')).replace(/^\uFEFF/,''));
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const disk=resource=>join(root,'godot',resource.replace(/^res:\/\//,''));
const resource=path=>path.startsWith('res://')?path:'res://'+path.replace(/^godot\//,'');
const exists=async p=>{try{await readFile(p);return true;}catch(error){if(error.code==='ENOENT')return false;throw error;}};
const scene=await read(join(folder,'scene-inventory.json'));
const ui=await read(join(folder,'ui-actor-inventory.json'));
const combined=await read(join(folder,'combined-source-groups.json'));
const visual=await read(join(root,'godot/content/visual-assets.json'));
const theme=await read(candidate?join(assetFolder,'theme.proposed.json'):join(root,'godot/content/element-theme.json'));
const bitmap=await read(candidate?join(assetFolder,'bitmap-redraw.proposed.json'):join(root,'godot/content/bitmap-redraw.json'));
const manifest=await read(join(assetFolder,'manifest.json'));
const previous=await read(join(root,'assets/images/scene-redraw-20261116/manifest.json'));
const sourcePaths=Object.fromEntries(visual.entries.map(e=>[e.id,e.resource]));
const themeSources={};
const errors=[];
for(const [alias,replacement]of Object.entries(theme.resource_overrides??{})){
 const original=sourcePaths[alias];
 if(!original){errors.push('Unknown theme alias: '+alias);continue;}
 if(themeSources[original]&&themeSources[original]!==replacement)errors.push('Conflicting same-source theme: '+original);
 themeSources[original]=replacement;
}
const effective=source=>themeSources[source]??bitmap.source_overrides?.[source]??source;
const outputs=new Map();
for(const entry of [...(previous.entries??[]),...(manifest.entries??[])]){
 const path=resource(entry.output.path);
 outputs.set(path,{batch:entry.master.path.includes('/scene-redraw-20261116/')?'previous-seven':'full-redraw',id:entry.id??entry.alias,output:entry.output,master:entry.master});
}
const required=new Map();
function add(path,kind,aliases=[],consumers=[],expectedSha=null){
 path=resource(path);
 if(!required.has(path))required.set(path,{source:path,kinds:[],aliases:[],consumers:[],originalSha256:expectedSha});
 const row=required.get(path);
 for(const [key,list]of [['kinds',[kind]],['aliases',aliases],['consumers',consumers]])for(const value of list)if(!row[key].includes(value))row[key].push(value);
}
for(const entry of scene.entries)if(entry.requiresRedraw)add(entry.resource,'scene',entry.aliases??[],entry.roles??[],entry.sha256);
for(const entry of ui.entries)if(entry.redrawRequired&&entry.action!=='regenerate-derivative'&&!entry.path.includes('/web/loader/'))add(entry.path,entry.categories?.includes('actor')?'actor':'ui',entry.aliases??[],entry.consumers??[],entry.sha256);
const rows=[];
for(const row of required.values()){
 const resolved=effective(row.source),proof=outputs.get(resolved),failures=[];
 let bytes=null,oldBytes=null;
 try{oldBytes=await readFile(disk(row.source));}catch{failures.push('missing-original');}
 if(row.originalSha256&&oldBytes&&sha(oldBytes)!==row.originalSha256)failures.push('original-changed');
 if(resolved===row.source)failures.push('still-original');
 try{bytes=await readFile(disk(resolved));}catch{failures.push('missing-output');}
 if(!proof)failures.push('no-generated-master-provenance');
 if(proof&&bytes&&sha(bytes)!==proof.output.sha256)failures.push('output-hash-differs');
 if(bytes&&oldBytes&&sha(bytes)===sha(oldBytes))failures.push('output-is-unchanged-old-bytes');
 if(proof&&(!(proof.output.alpha8?.rect?.[2]>0)||!(proof.output.alpha8?.rect?.[3]>0)))failures.push('empty-visible-output');
 if(proof&&!(await exists(join(root,proof.master.path))))failures.push('missing-generated-master');
 if(proof&&bytes&&oldBytes&&bytes.subarray(1,4).toString()==='PNG'&&oldBytes.subarray(1,4).toString()==='PNG'){
  if(bytes.readUInt32BE(16)!==oldBytes.readUInt32BE(16)||bytes.readUInt32BE(20)!==oldBytes.readUInt32BE(20))failures.push('logical-canvas-changed');
 }
 for(const alias of row.aliases){
  const aliasSource=sourcePaths[alias];
  if(aliasSource&&effective(aliasSource)!==resolved)failures.push('alias-source-disagrees:'+alias);
 }
 rows.push({...row,resolved,provenance:proof?{batch:proof.batch,id:proof.id,master:proof.master.path,masterSha256:proof.master.sha256}:null,failures,covered:failures.length===0});
}
const actorGroups=combined.groups.filter(g=>g.paths.some(p=>/character-refined|menu-walk\/step-|journey-gardens\/buddy-ball/.test(p)));
const actors=actorGroups.map(group=>{
 const members=group.paths.map(path=>rows.find(row=>row.source===resource(path))).filter(Boolean);
 return {originalSha256:group.sha256,members:members.map(row=>row.source),resolved:[...new Set(members.map(row=>row.resolved))],covered:members.length===group.paths.length&&members.every(row=>row.covered)};
});
// Direct image load sites would bypass the shared resolver. Only production UI
// and native scenery are scanned, never test fixtures that intentionally compare.
const bypasses=[];
async function scan(path){
 for(const item of await readdir(path,{withFileTypes:true})){
  const file=join(path,item.name);
  if(item.isDirectory())await scan(file);
  else if(item.name.endsWith('.gd')){
   const code=await readFile(file,'utf8');
   for(const match of code.matchAll(/\b(?:preload|load)\s*\(\s*["'](res:\/\/assets\/images\/[^"']+)["']/g)){
    if(required.has(match[1]))bypasses.push({file:file.slice(root.length+1).replaceAll('\\','/'),line:code.slice(0,match.index).split(/\r?\n/).length,source:match[1]});
   }
  }
 }
}
await scan(join(root,'godot/ui'));
await scan(join(root,'godot/presentation/native'));
const loader=await read(join(root,'godot/web/loader/manifest.json'));
const logo=loader.assets.find(e=>e.file==='logo.png');
const logoSource='res://assets/images/material-ready/menu-logo.png';
const expectedLogo='godot/'+effective(logoSource).replace(/^res:\/\//,'');
const loaderSourceMatches=logo?.source===expectedLogo||(!candidate&&effective(logoSource)===logoSource&&logo?.source==='assets/images/material-ready/menu-logo.png');
const covered=rows.filter(row=>row.covered).length;
const passed=covered===rows.length&&bypasses.length===0&&errors.length===0&&actors.every(row=>row.covered)&&loaderSourceMatches;
const report={suite:'full-redraw-path-coverage',candidate,passed,scope:'Frozen current native scene/UI/actor consumer paths, effective theme/bitmap resolution and generated-master/output hashes. No GPU, pointer input, visual acceptance or independently re-encoded loader-byte claim.',requiredPaths:rows.length,coveredPaths:covered,remainingPaths:rows.length-covered,actorUniqueGroups:actors.length,coveredActorGroups:actors.filter(row=>row.covered).length,errors,bypasses,loader:{source:logo?.source??null,expectedSource:expectedLogo,sourceMatches:loaderSourceMatches,byteCheck:'Run sync-loading-assets.py --check after final generation; this audit checks declared source identity only.'},rows,actorGroups:actors};
await mkdir(dirname(output),{recursive:true});
await writeFile(output,JSON.stringify(report,null,2)+'\n');
await writeFile(output.replace(/\.json$/,'.requirements.json'),JSON.stringify({schema_version:1,sourcePaths:rows.map(row=>({source:row.source,aliases:row.aliases,kinds:row.kinds})),scope:'Frozen old-cutout consumer requirement paths for native runtime resolver/actor verification.'},null,2)+'\n');
console.log(JSON.stringify({passed,candidate,required:rows.length,covered,remaining:rows.length-covered,actors:actors.length,bypasses:bypasses.length,loaderSourceMatches,output:output.slice(root.length+1)}));
if(!passed&&!allowPartial)process.exitCode=1;
