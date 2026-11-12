import {createHash} from 'node:crypto';
import {copyFile, mkdir, readFile, stat, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

// Mirror the effective world, HUD and cover assets, not entire source art folders.
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const sourceRoot=path.join(root,'assets/images');
const targetRoot=path.join(root,'godot/assets/images');
const manifestPath=path.join(root,'godot/content/visual-assets.json');
const entries=new Map();
const add=(id,file,anchor=[.5,.9],group='world')=>entries.set(id,{id,source:`assets/images/${file}`,resource:`res://assets/images/${file}`,file,anchor,group});
for(const id of ['stone','grass','stairs','arch','rock','flowers','crystal','lilypad','bush'])add(id,`grid-world/${id}.png`);
for(const id of ['flower','bloom','vine','light','bug'])add(id,`production/${id}.png`);
const character=['idle-front','idle-side','idle-back','idle-quarter','jump','interact','lean','salute','symbiosis',...Array.from({length:12},(_,i)=>`walk-${i+1}`),...Array.from({length:12},(_,i)=>`walk-back-${i+1}`),...Array.from({length:12},(_,i)=>`jump-${i+1}`),...Array.from({length:5},(_,i)=>`sow-${i+1}`)];
for(const id of character)add(id,`character-refined/${id}.png`,[.5,236/256],'character');
// Existing articulated side cycle preserves the in-game character artwork.
for(let frame=1;frame<=12;frame++)add(`walk-side-${frame}`,`menu-walk/step-${frame}.png`,[.5,236/256],'character');
add('portrait-front','character-refined/portrait-front.png',[.5,.5],'ui');
for(const id of ['dew-plant','dew-parcel','berry-bush','river-rock','pebble-cluster','small-pebbles','stone-lantern','gold-lotus','trailing-vine','pink-flowers','ivory-lotus','glow-flower','fern','blue-flowers','yellow-flowers','red-mushroom','blue-mushroom','wood-lantern','violet-crystal','light-tower','lotus-pool','flower-gate-frame','flower-gate-seal'])add(id,`garden-scenery/${id}.png`);
for(const id of ['paving-valley','paving-pond','paving-grass','paving-moss','valley-wall-left','valley-wall-right','masonry-valley','masonry-pond','water-pigment'])add(id,`garden-scenery/${id}.jpg`);
for(const id of ['wall-left','wall-right'])add(id,`grid-world/${id}.jpg`);
add('background-valley','grid-world/sky-valley.jpg',[.5,.5],'background');
add('background-cave','grid-world/sky-cave.jpg',[.5,.5],'background');
add('background-pond','garden-scenery/pond-rain-forest-v2.png',[.5,.5],'background');
// In the original renderer this intentionally replaces character-refined/ball.png.
add('ball','journey-gardens/buddy-ball.png',[.5,.5],'character');
add('spore','material-ready/icon-spore.png',[.5,.5]);
for(const id of ['pause','map','spore','back','undo','roll','sow','hint','retry','settings','music','sound','leaf']){
 const file=`material-ready/icon-${id}.png`;
 try{await stat(path.join(sourceRoot,file));add(`icon-${id}`,file,[.5,.5],'ui');}catch(error){if(error.code!=='ENOENT')throw error;}
}
for(const id of ['panel-paper','button-paper','button-green'])add(id,`material-ready/${id}.png`,[.5,.5],'ui');
add('paper-texture','gallery-journal/paper-texture.jpg',[0,0],'ui');
for(const [id,file] of [['gallery-vine','gallery-journal/vine.png'],['gallery-mushroom','gallery-journal/mushroom.png'],['gallery-lily','production/lily-open.png'],['gallery-arch','production/arch.png'],['gallery-cave-bloom','reference-scenes/plant-cave-bloom.png']])add(id,file,[.5,.5],'gallery');
// Original illustrated chapter maps; live native controls cover baked counters.
for(const chapter of ['valley','pond','cave']){
 add(`map-${chapter}`,`reference-scenes/map-${chapter}.jpg`,[.5,.5],'chapter-map');
 add(`chapter-${chapter}`,`reference-scenes/chapter-${chapter}.jpg`,[.5,.5],'chapter-map');
}
for(const id of ['plant-bud','plant-dormant','plant-bloom','plant-pond-bloom'])add(`map-${id}`,`reference-scenes/${id}.png`,[.5,.5],'chapter-map');
add('map-terrain-steps','reference-scenes/terrain-steps.png',[.5,.5],'chapter-map');
add('map-moss','production/moss.png',[.5,.5],'chapter-map');
// The original cover is an illustrated animated scene, not a generic menu modal.
for(const id of ['idle-front','idle-side','crouch-lower','crouch','crouch-happy','turn-quarter',...Array.from({length:8},(_,i)=>`step-${i+1}`)])add(`cover-${id}`,`menu-walk-redrawn/${id}.png`,[.5,236/256],'cover');
for(const id of ['orb','firefly'])add(`cover-${id}`,`menu-fx-redrawn/${id}.png`,[.5,.5],'cover');
for(const [id,file] of [['cover-background','main/bg.png'],['cover-logo','material-ready/menu-logo.png'],['cover-paper','material-ready/menu-paper.png']])add(id,file,[.5,.5],'cover');

function dimensions(buffer){
 if(buffer.subarray(1,4).toString()==='PNG')return {width:buffer.readUInt32BE(16),height:buffer.readUInt32BE(20),alpha:[4,6].includes(buffer[25])};
 let offset=2;
 while(offset+9<buffer.length){
  if(buffer[offset]!==0xff){offset++;continue;}
  const marker=buffer[offset+1];offset+=2;
  if(marker===0xd8||marker===0xd9)continue;
  const length=buffer.readUInt16BE(offset);
  if([0xc0,0xc1,0xc2].includes(marker))return {width:buffer.readUInt16BE(offset+5),height:buffer.readUInt16BE(offset+3),alpha:false};
  if(length<2)break;offset+=length;
 }
 throw new Error('Unsupported image header');
}
const hash=buffer=>createHash('sha256').update(buffer).digest('hex');
const rows=[];
for(const entry of entries.values()){
 const buffer=await readFile(path.join(sourceRoot,entry.file));
 rows.push({...entry,...dimensions(buffer),bytes:buffer.length,sha256:hash(buffer),filter:'linear',repeat:entry.file.endsWith('.jpg')?'enabled':'disabled'});
}
rows.sort((a,b)=>a.id.localeCompare(b.id));
const manifest={version:1,baseline:'5791bbc3dd90549b4c7ea302507ead577f51dd67',projection:{tile_width:70,tile_height:35,height_rise:48},notes:['Only effective world, HUD and animated cover texture aliases are copied.','Images retain their original bytes; procedural Canvas art is rebuilt by presentation scripts.','The ball alias resolves to journey-gardens/buddy-ball.png as in GardenRenderer.'],entries:rows};
if(process.argv.includes('--dry-run')){
 console.log(JSON.stringify({mode:'dry-run',assets:rows.length,bytes:rows.reduce((n,e)=>n+e.bytes,0)},null,2));
}else if(process.argv.includes('--check')){
 const saved=JSON.parse(await readFile(manifestPath,'utf8'));
 if(JSON.stringify(saved)!==JSON.stringify(manifest))throw new Error('Visual manifest differs from source whitelist. Run sync-assets.mjs.');
 for(const entry of rows){const copied=await readFile(path.join(targetRoot,entry.file));if(hash(copied)!==entry.sha256)throw new Error(`Asset hash mismatch: ${entry.id}`);}
 console.log(`PASS ${rows.length} visual aliases, source and copied SHA-256 match`);
}else{
 for(const entry of rows){const destination=path.join(targetRoot,entry.file);await mkdir(path.dirname(destination),{recursive:true});await copyFile(path.join(sourceRoot,entry.file),destination);}
 await mkdir(path.dirname(manifestPath),{recursive:true});
 await writeFile(manifestPath,`${JSON.stringify(manifest,null,2)}\n`);
 console.log(`Synced ${rows.length} visual aliases without changing original assets`);
}
