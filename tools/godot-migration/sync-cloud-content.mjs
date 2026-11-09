import {readFile,writeFile} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const require=createRequire(import.meta.url);
const ts=require('typescript');
const source=await readFile(resolve(root,'src/app/cloud/data.ts'),'utf8');
const compiled=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText;
const original=await import('data:text/javascript;base64,'+Buffer.from(compiled).toString('base64'));
const kind={turn:'turn',seed:'item',finish:'core',dock:'valve',valve:'valve',pad:'plate',latch:'lever'};
const levels=original.CLOUD_LEVELS.map(level=>{
 const tiles=original.cloudTiles(level.id,level.id==='cloud-3'?'east':'north','low',false);
 const marks=level.landmarks.map(mark=>({
  id:mark.id,tile:original.tileId(mark.x,mark.z,mark.id==='valve'?'lift':'floor'),
  label:mark.label,kind:mark.story?'observe':kind[mark.id]??'observe',
  text:mark.story??'',x:mark.x,z:mark.z,h:mark.h
 }));
 return {...level,chapter:'cloud',companionMode:'cloud',dual:false,total:2,rule:level.subtitle,intro:level.subtitle,
 story:level.story,roots:[],modules:[],collectibles:[],marks,tiles};
});
await writeFile(resolve(root,'godot/content/cloud-levels.json'),JSON.stringify({version:1,source:'src/app/cloud/data.ts',levels},null,2)+'\n');
console.log('Cloud definitions: '+levels.length+' levels from original data');

