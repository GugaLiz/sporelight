import {createRequire} from 'node:module';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
const root=process.cwd();
const require=createRequire(import.meta.url);
let sharp;try{sharp=require('sharp');}catch{sharp=require(join(process.env.USERPROFILE,'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp'));}
const folder=join(root,'docs/qa-godot-native/full-asset-redraw-20261116');
const runtime=JSON.parse(await readFile(join(folder,'scene-runtime-usage.json'),'utf8'));
const manifest=JSON.parse(await readFile(join(root,'godot/content/visual-assets.json'),'utf8'));
const props=JSON.parse(await readFile(join(root,'godot/content/prop-elements.json'),'utf8'));
const pathAliases={};
for(const entry of manifest.entries)(pathAliases[entry.resource]??=[]).push(entry.id);
for(const [alias,path]of Object.entries(props.resources))(pathAliases[path]??=[]).push(alias);
const newTheme=JSON.parse(await readFile(join(root,'godot/content/element-theme.json'),'utf8'));
for(const [alias,path]of Object.entries(newTheme.resource_overrides??{}))(pathAliases[path]??=[]).push(alias);
const bound=runtime.boundResources.filter(entry=>!entry.roles.every(role=>role.startsWith('actor-frame/')));
const resources=new Map(bound.map(entry=>[entry.resource,entry]));
// Sources consumed into generated carry or SVG textures are not bound to the
// eventual Sprite3D directly. These uses are proved by the named source code.
const composited=[
 {alias:'dew-parcel',file:'garden-scenery/dew-parcel.png',consumer:'original_carry_art.gd:24,72-85',levels:['2-1','3-3'],role:'carry-thumbnail-source'},
 {alias:'crystal',file:'grid-world/crystal.png',consumer:'original_carry_art.gd:23-26,72-85',levels:['2-4'],role:'carry-thumbnail-source; other crystal loads are overwritten placeholders'},
 {alias:'stone',file:'grid-world/stone.png',consumer:'original_sanctuary_dressing.gd:_stone_grain',levels:['1-4'],role:'CPU-composited stone grain, interior samples only'},
 {alias:'background-valley',file:'grid-world/sky-valley.jpg',consumer:'native_garden_stage.gd:_draw',levels:['1-1','1-2','1-3','1-4'],role:'canvas-background'},
 {alias:'background-cave',file:'grid-world/sky-cave.jpg',consumer:'native_garden_stage.gd:_draw',levels:['3-1','3-2','3-3','3-4'],role:'canvas-background'},
];
for(const entry of composited){
 const resource='res://assets/images/'+entry.file;
 if(!resources.has(resource))resources.set(resource,{resource,uses:entry.levels.map(x=>x+':static-composite-source'),visibleUses:entry.levels.map(x=>x+':static-composite-source'),nodes:[],roles:[entry.role],staticEvidence:entry.consumer});
}
const generatedPrefixes=['res://assets/images/scene-redraw-20261116/','res://assets/images/shadow-stones/','res://assets/images/symbiosis/'];
const oldProof={
 'garden-scenery':'scripts/prepare_garden_scenery.py: source sheet crops + edge-connected neutral removal',
 'grid-world':'scripts/prepare_grid_assets.py: source sheet crops + edge-connected neutral removal',
 'production':'scripts/prepare_assets.py: source raster crop + remove_checker / glow alpha processing',
};
const entries=[];
for(const entry of resources.values()){
 const file=join(root,'godot',entry.resource.slice(6));
 const bytes=await readFile(file);
 const {data,info}=await sharp(bytes).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 let clear=0,partial=0,opaque=0;let left=info.width,top=info.height,right=-1,bottom=-1;
 for(let y=0;y<info.height;y++)for(let x=0;x<info.width;x++){
  const alpha=data[(y*info.width+x)*4+3];
  if(alpha===0)clear++;else if(alpha===255)opaque++;else partial++;
  if(alpha>=8){left=Math.min(left,x);top=Math.min(top,y);right=Math.max(right,x);bottom=Math.max(bottom,y);}
 }
 const isNew=generatedPrefixes.some(prefix=>entry.resource.startsWith(prefix));
 const category=entry.resource.split('/')[4];
 let classification='opaque-texture-or-background',requiresRedraw=false,reason='Complete opaque surface/background image; no cutout silhouette.';
 if(isNew){classification='already-original-redraw';reason='Versioned generated source retained and current element theme/natural_assets provenance; not an old source-sheet extraction.';}
 else if(clear>0&&oldProof[category]){
  classification='old-sheet-cutout';requiresRedraw=true;reason=oldProof[category];
 }
 const aliases=[...new Set(pathAliases[entry.resource]??[])];
 let risk='Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale.';
 if(aliases.some(x=>['stone-lantern','rock','river-rock','light-tower','flower-gate-frame','flower-gate-seal','lotus-pool'].includes(x)))risk+=' Full hard-base footprint and navigation/depth alignment must be reviewed separately from foliage.';
 if(aliases.includes('stairs'))risk='Interior paint-source is sampled by PaintedStoneUV.sample using fixed 142x147 source pixels; preserve sampled tread/riser quadrilaterals, not only silhouette.';
 if(aliases.includes('stone'))risk='Only interior grain is composited into the code-native fountain; source outer cutout edge is not displayed. Keep sampled stone face coverage; no geometry change.';
 if(aliases.some(x=>x.startsWith('dew-')))risk+=' Dew plant ground state and carried parcel are separate assets; do not turn either into a new puzzle object.';
 if(aliases.some(x=>x.startsWith('flower-gate-')))risk+=' Frame/seal are a registered pair split from light-tower; preserve transparent doorway/membrane mask and independent seal fade.';
 entries.push({...entry,aliases,path:file.replaceAll('\\','/').slice(root.replaceAll('\\','/').length+1),canvas:[info.width,info.height],sha256:createHash('sha256').update(bytes).digest('hex'),alpha:{clear,partial,opaque,alpha8Bounds:right<0?[0,0,0,0]:[left,top,right-left+1,bottom-top+1]},classification,requiresRedraw,classificationEvidence:reason,levels:[...new Set(entry.visibleUses.map(x=>x.split(':')[0]))],anchorRisk:risk});
}
entries.sort((a,b)=>a.resource.localeCompare(b.resource));
const report={scope:runtime.scope,sampledLevelCount:15,sampledStateCount:runtime.sampledStates.length,provenance:'Runtime TracedStage plus actual sprite/material bindings; carry/fountain/background direct consumers added by code inspection. This audit is reachability/resource evidence, not visual acceptance.',counts:{sceneResources:entries.length,oldCutoutResources:entries.filter(e=>e.requiresRedraw).length,alreadyRedrawnResources:entries.filter(e=>e.classification==='already-original-redraw').length,opaqueTextures:entries.filter(e=>e.classification==='opaque-texture-or-background').length},excludedActorFrameResources:runtime.boundResources.length-bound.length,generatedNodeTextureCount:runtime.generatedNodeTextures.length,generatedNativeNotes:['Cloud architecture/flowers/birds/lanterns/waterfall are original SVG via original_cloud_art.gd, not sheet cutouts.','Fountain, gate trim, rain keyboard, optical fixtures, pathway glow and water particles include native SVG/mesh/shader artwork; not automatically cutouts because rendered into ImageTexture.'],unboundLoads:Object.entries(runtime.stageTextureCalls).filter(([alias,v])=>!resources.has(v.resource)&&!alias.match(/^(walk|idle|jump|sow|interact|lean|salute|symbiosis|portrait|ball)/)).map(([alias,value])=>({alias,...value,reason:'Load does not establish a displayed pixel consumer; may be a temporary placeholder overwritten by natural/SVG art.'})),entries};
await writeFile(join(folder,'scene-inventory.json'),JSON.stringify(report,null,2)+'\n');
const cutouts=entries.filter(e=>e.requiresRedraw);
const cellW=180,cellH=182,columns=5;
const images=[];
for(let i=0;i<cutouts.length;i++){
 const item=cutouts[i];
 const thumb=await sharp(join(root,item.path)).resize(154,140,{fit:'inside'}).png().toBuffer();
 const meta=await sharp(thumb).metadata();
 const x=(i%columns)*cellW,y=Math.floor(i/columns)*cellH;
 images.push({input:thumb,left:x+Math.floor((cellW-meta.width)/2),top:y+Math.floor((142-meta.height)/2)+4});
 const label=item.aliases.join('/').replaceAll('&','&amp;');
 images.push({input:Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="180" height="36"><text x="7" y="17" fill="#203b31" font-size="12" font-family="Arial">${label}</text><text x="7" y="32" fill="#4d6755" font-size="11" font-family="Arial">${item.canvas.join('x')}</text></svg>`),left:x,top:y+145});
}
await sharp({create:{width:columns*cellW,height:Math.ceil(cutouts.length/columns)*cellH,channels:3,background:'#e8ddba'}}).composite(images).png().toFile(join(folder,'scene-cutout-contact-sheet.png'));
console.log(JSON.stringify({counts:report.counts,cutouts:cutouts.map(e=>e.aliases.join('/'))}));
