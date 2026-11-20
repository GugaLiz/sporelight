import {readFile,writeFile,mkdir,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {dirname,join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const require=createRequire(import.meta.url);
let sharp;try{sharp=require('sharp');}catch{sharp=require(join(process.env.USERPROFILE,'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp'));}
const manifest=JSON.parse(await readFile(join(root,'godot/content/visual-assets.json'),'utf8'));
const aliases=new Map(manifest.entries.map(e=>[e.id,e]));
const theme=JSON.parse(await readFile(join(root,'godot/content/element-theme.json'),'utf8'));
const actors=JSON.parse(await readFile(join(root,'godot/content/actor-elements.json'),'utf8'));
const byPath=new Map();
function add(file,consumer,category,detail={}){
 file=file.replace(/^res:\/\//,'');if(!file.startsWith('assets/'))file='assets/images/'+file;
 const key='godot/'+file;
 if(!byPath.has(key))byPath.set(key,{path:key,aliases:manifest.entries.filter(e=>e.resource==='res://'+file).map(e=>e.id),consumers:[],categories:[],...detail});
 const row=byPath.get(key);if(!row.consumers.includes(consumer))row.consumers.push(consumer);if(!row.categories.includes(category))row.categories.push(category);
}
const clips=[];
for(const[skin,spec]of Object.entries(actors.skins))for(const[clip,entry]of Object.entries(spec.clips)){
 clips.push({skin,clip,frames:entry.frames,fps:entry.fps,loop:entry.loop});
 for(const alias of entry.frames){if(alias.startsWith('@'))continue;const asset=aliases.get(alias);if(asset)add(asset.resource,'actor-elements.json:'+skin+'/'+clip,'actor');}
}
for(const name of await readdir(join(root,'godot/ui'))){
 if(!name.endsWith('.gd'))continue;
 const source=await readFile(join(root,'godot/ui',name),'utf8');
 for(const match of source.matchAll(/["']((?:res:\/\/assets\/images\/)?[a-z0-9-]+\/[a-z0-9._/-]+\.(?:png|jpg|webp))["']/gi))add(match[1],'godot/ui/'+name,'ui');
}
for(const key of ['idle-front','cover-idle-side',...Array.from({length:8},(_,i)=>'cover-step-'+(i+1))])add(aliases.get(key).resource,'godot/ui/menu_vignette.gd:themed actor slot '+key,'cover');
for(const chapter of ['valley','pond','cave'])for(const prefix of ['map','chapter'])add('reference-scenes/'+prefix+'-'+chapter+'.jpg','godot/ui/chapter_map.gd:dynamic chapter '+chapter,'chapter-map');
for(const state of ['plant-bud','plant-dormant','plant-bloom','plant-pond-bloom','plant-cave-bloom'])add('reference-scenes/'+state+'.png','godot/ui/chapter_map.gd:landmark state '+state,'chapter-map');
for(const file of ['bg.webp','logo.png','hero.png','orb.png']){
 const key='godot/web/loader/'+file;byPath.set(key,{path:key,aliases:[],consumers:['godot/web/loading-shell.html'],categories:['web-loader']});
}
function provenance(row){
 const p=row.path;
 if(p.includes('/cover-identity-20261118/'))return {classification:'already-redrawn-rgba',redrawRequired:false,evidence:['assets/images/cover-identity-20261118/generation.json','assets/images/cover-identity-20261118/registration.json','docs/117-首页追光与行走托光人物连续性修复.md'],reason:'Quarter-view gaze edit referenced directly to idle, walk and palm identity; closed smile, uniform scale and boot registration, source alpha retained.'};
 if(p.includes('/cover-proportions-20261118/'))return {classification:'already-redrawn-rgba',redrawRequired:false,evidence:['assets/images/cover-proportions-20261118/generation.json','assets/images/cover-proportions-20261118/registration.json','tools/godot-migration/check-cover-proportions.py'],reason:'Whole generated gaze/gesture redraw with painted cap/body metrics compared against existing idle; shared scale and boot registration retain alpha.'};
 if(p.includes('/cover-attention-20261118/'))return {classification:'already-redrawn-rgba',redrawRequired:false,evidence:['assets/images/cover-attention-20261118/generation.json','assets/images/cover-attention-20261118/registration.json','tools/godot-migration/prepare-cover-attention-art.mjs'],reason:'Complete generated directional gaze/gesture poses, uniformly scaled and registered at boot centers; original alpha retained.'};
 if(p.includes('/cover-palm-20261118/'))return {classification:'already-redrawn-rgba',redrawRequired:false,evidence:['assets/images/cover-palm-20261118/generation.json','assets/images/cover-palm-20261118/registration.json','tools/godot-migration/prepare-cover-palm-art.mjs'],reason:'Whole generated reach/hold poses, one uniform scale and registered feet/palms; source alpha preserved.'};
 if(p.includes('/menu-walk-redrawn/'))return {classification:'already-redrawn-rgba',redrawRequired:false,evidence:['assets/images/menu-walk-redrawn/manifest.json','assets/images/menu-walk-redrawn/poses-manifest.json','scripts/import_menu_redraw.py','scripts/import_menu_poses.py'],reason:'Whole generated poses; packaging retains generated alpha. Atlas slicing is not background extraction.'};
 if(p.includes('/menu-fx-redrawn/'))return {classification:'already-redrawn-rgba',redrawRequired:false,evidence:['docs/21-首页追光小剧场.md'],reason:'Imagegen-authored orb/firefly, generated transparency retained.'};
 if(p.endsWith('/main/bg.png')||/reference-scenes\/(?:chapter|map)-/.test(p))return {classification:'opaque-complete-illustration',redrawRequired:false,evidence:['scripts/prepare_reference_scenes.py','godot/ui/menu_vignette.gd'],reason:'Complete painted scene, not a foreground silhouette with removed background. Chapter grading and removal of baked labels do not make it a cutout prop.'};
 if(p.endsWith('/paper-texture.jpg'))return {classification:'opaque-texture-sample',redrawRequired:false,evidence:['scripts/prepare_gallery_assets.py'],reason:'Rectangular parchment grain used as fill, not a cutout element.'};
 if(p.includes('/character-refined/'))return {classification:'legacy-character-cutout-or-derived-frame',redrawRequired:true,evidence:['assets/images/character-refined/manifest.json','scripts/prepare_material_assets.py','scripts/character_matte.py'],reason:'Manifest explicitly records crop/background extraction and compositing rather than AI redrawing; a smooth matte alone does not change this provenance.'};
 if(p.includes('/menu-walk/'))return {classification:'legacy-cutout-articulated-frame',redrawRequired:true,evidence:['scripts/prepare_menu_walk.py'],reason:'Arm/legs are cut from character-refined/idle-side.png and rotated/composited. This cycle is used by in-game actor clips, despite the home cover using newly redrawn frames.'};
 if(p.endsWith('/journey-gardens/buddy-ball.png'))return {classification:'legacy-checker-cutout',redrawRequired:true,evidence:['scripts/prepare_journey_gardens.py'],reason:'Source mushroom-ball reference has boundary-connected checker removed. Shared by rolling poses and procedural companion cap texture.'};
 if(p.includes('/material-ready/'))return {classification:'legacy-ui-cutout',redrawRequired:true,evidence:['scripts/prepare_material_assets.py','assets/images/material-ready/manifest.json'],reason:'UI sheet crop and connected-background removal. Panel ornaments have source-pixel crop consumers; replacements must retain those regions.'};
 if(p.includes('/reference-scenes/')&&p.endsWith('.png'))return {classification:'legacy-map-cutout-composite',redrawRequired:true,evidence:['scripts/prepare_reference_scenes.py'],reason:'Background-keyed foreground plants, original soil base and terrain crop composited into transparent sprites.'};
 if(p.includes('/production/'))return {classification:'legacy-sheet-cutout',redrawRequired:true,evidence:['scripts/prepare_assets.py'],reason:'Existing raster sheet isolated with edge-connected checker/background removal. Direct UI file paths currently bypass the world theme.'};
 if(p.includes('/gallery-journal/'))return {classification:'legacy-gallery-cutout',redrawRequired:true,evidence:['scripts/prepare_gallery_assets.py'],reason:'Foreground illustration extracted from gallery reference page and edge-connected parchment removed.'};
 if(p.includes('/garden-scenery/')||p.includes('/grid-world/'))return {classification:'shared-scene-prop-review-in-scene-inventory',redrawRequired:true,evidence:['scripts/prepare_garden_scenery.py','scripts/prepare_grid_assets.py'],reason:'Direct UI reuse of a scene prop; merge by original path with scene audit to avoid duplicate generation.'};
 if(p.endsWith('/loader/bg.webp'))return {classification:'opaque-loader-derivative',redrawRequired:false,evidence:['tools/godot-migration/sync-loading-assets.py'],reason:'Derived from complete opaque home backdrop.'};
 if(p.endsWith('/loader/logo.png'))return {classification:'legacy-ui-cutout-derivative',redrawRequired:true,derivedFrom:'assets/images/material-ready/menu-logo.png',evidence:['tools/godot-migration/sync-loading-assets.py'],reason:'Loader copy of old cutout logo; regenerate mechanically after its source is redrawn, no separate image generation.'};
 if(p.includes('/loader/'))return {classification:'already-redrawn-loader-derivative',redrawRequired:false,evidence:['tools/godot-migration/sync-loading-assets.py'],reason:'Derived from already redrawn menu hero/orb; regenerate only when source changes.'};
 return {classification:'needs-review',redrawRequired:null,evidence:[],reason:'No automatic provenance assumption.'};
}
const entries=[];
for(const row of byPath.values()){
 const bytes=await readFile(join(root,row.path));const metadata=await sharp(bytes).metadata();
 const{data,info}=await sharp(bytes).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 let transparent=0,opaque=0,partial=0,minx=info.width,miny=info.height,maxx=-1,maxy=-1;
 for(let y=0;y<info.height;y++)for(let x=0;x<info.width;x++){const a=data[(y*info.width+x)*info.channels+3];if(a===0)transparent++;else if(a===255)opaque++;else partial++;if(a>=8){minx=Math.min(minx,x);miny=Math.min(miny,y);maxx=Math.max(maxx,x);maxy=Math.max(maxy,y);}}
 const origin=provenance(row);
 const available=manifest.entries.filter(e=>'godot/'+e.resource.replace(/^res:\/\//,'')===row.path).map(e=>theme.resource_overrides[e.id]).find(Boolean);
 entries.push({...row,...origin,availableRedraw:available??null,action:available&&origin.redrawRequired?'rebind-existing-redraw':origin.redrawRequired?(origin.derivedFrom?'regenerate-derivative':'redraw-master'):'keep',canvas:[metadata.width,metadata.height],sha256:createHash('sha256').update(bytes).digest('hex'),alpha:{transparent,opaque,partial,partialOfVisible:partial/(opaque+partial||1),bounds8:maxx>=0?[minx,miny,maxx-minx+1,maxy-miny+1]:[0,0,0,0]}});
}
entries.sort((a,b)=>a.path.localeCompare(b.path));
const groups={};for(const e of entries){(groups[e.classification]??=[]).push(e.path);}
const hashes=new Map();for(const e of entries){if(!hashes.has(e.sha256))hashes.set(e.sha256,[]);hashes.get(e.sha256).push(e.path);}
const output=join(root,'docs/qa-godot-native/full-asset-redraw-20261116');await mkdir(output,{recursive:true});
const report={date:'2026-11-16',scope:'Godot current native actor skins, UI/cover/maps/gallery and Web loading shell. Static path/clip audit plus alpha statistics, not a GPU runtime-visibility proof. Scene props shared with UI must be deduplicated by path against scene inventory.',method:'Actual UI source consumers + actor-elements clip arrays; explicit expansion of dynamic cover and map keys. Imported but unreferenced legacy assets are not automatically included.',summary:{paths:entries.length,uniqueBytes:hashes.size,oldCutoutPaths:entries.filter(x=>x.redrawRequired===true).length,redrawMasterPaths:entries.filter(x=>x.action==='redraw-master').length,redrawMasterUniqueBytes:new Set(entries.filter(x=>x.action==='redraw-master').map(e=>e.sha256)).size,rebindExistingRedrawPaths:entries.filter(x=>x.action==='rebind-existing-redraw').length,derivativePaths:entries.filter(x=>x.action==='regenerate-derivative').length,actorFilePaths:entries.filter(x=>x.categories.includes('actor')).length,actorUniqueBytes:new Set(entries.filter(x=>x.categories.includes('actor')).map(e=>e.sha256)).size},clips,groups,entries,duplicateByteGroups:[...hashes.values()].filter(a=>a.length>1),proceduralResources:[{id:'@procedural_buddy',source:'godot/presentation/actors/creature_art.gd',note:'Programmatic painted body/eyes/leaf/feet. Cap samples old buddy-ball.png, so update that texture while preserving generated body and animation.'},{id:'carry leaf pouch / cord / bell thumbnail',source:'godot/presentation/native/original_carry_art.gd',note:'Programmatic SVG/raster composition with shared prop thumbnail; no independent photographed cutout.'}],excludedImportedExamples:['character-refined/portrait-front.png (no current native consumer found)','material-ready/icon-pause.png and most icon-*.png (only unused helper; no live button call sites)','gallery-journal/reading-companion.png, card-paper.png, detail-paper.png, book-scene.jpg (not consumed by current native UI)'],integrationRisks:['UI direct load/preload file paths bypass ElementAssets/theme; world-only alias overrides do not update map detail art, gallery or logo/loader.','Regenerate loader/logo.png from new logo source; do not generate a separate mismatching logo.','53 hero frame PNGs derive from cutouts. Preserve full walk clip phase, foot registrations, pose_overrides and fps; do not replace only idle or rewarp the old cutout body.','Map 5 landmark states share one soil base; preserve completed/locked identity and layout geometry.','GameHUD panel ornaments crop exact source-pixel rectangles; new panel must retain same canvas and decoration locations.','Logo contains Chinese/Latin branding and requires exact lettering review.']};
await writeFile(join(output,'ui-actor-inventory.json'),JSON.stringify(report,null,2)+'\n');
if(process.argv.includes('--contact-sheets')){
 for(const[name,predicate]of [['ui-actor-unique',e=>e.categories.includes('actor')],['ui-cutout-unique',e=>e.redrawRequired&&!e.categories.includes('actor')&&!e.derivedFrom]]){
  const seen=new Set();const selected=entries.filter(e=>predicate(e)&&!seen.has(e.sha256)&&seen.add(e.sha256));
  const cell=180,cols=6,rows=Math.ceil(selected.length/cols),layers=[];
  for(let i=0;i<selected.length;i++){
   const e=selected[i],x=i%cols*cell,y=Math.floor(i/cols)*cell;
   const image=await sharp(join(root,e.path)).resize(152,142,{fit:'contain',background:{r:0,g:0,b:0,alpha:0}}).png().toBuffer();
   layers.push({input:image,left:x+14,top:y+3});
   const label=e.path.split('/').at(-1).replaceAll('&','&amp;').replaceAll('<','&lt;');
   const svg=`<svg width="180" height="32"><text x="90" y="13" text-anchor="middle" font-family="Arial" font-size="12" fill="#34483c">${label}</text><text x="90" y="28" text-anchor="middle" font-family="Arial" font-size="10" fill="#68746c">${e.canvas.join('x')} ${e.action}</text></svg>`;
   layers.push({input:Buffer.from(svg),left:x,top:y+146});
  }
  await sharp({create:{width:cols*cell,height:rows*cell,channels:4,background:'#e8e5d4'}}).composite(layers).png().toFile(join(output,name+'.png'));
 }
}
console.log(JSON.stringify(report.summary));console.log(JSON.stringify(Object.fromEntries(Object.entries(groups).map(([k,v])=>[k,v.length]))));
