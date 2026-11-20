import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {sourceDigest} from '../tools/godot-migration/source-digest.mjs';
const root='G:/works/liuli/sporelight';
const variant='completion-sheet-20261119-final';
const dir=root+'/godot/build/'+variant;
const build=JSON.parse(await readFile(dir+'/build.json','utf8'));
const current=await sourceDigest(root);
const live=await (await fetch('http://localhost:4222/__build.json')).json();
if(current.sha256!==build.source.sha256 || current.sha256!==live.source.sha256)throw Error('Source/live build mismatch');
const files=['index.html','index.js','index.wasm','index.pck',...build.browserAssets.map(a=>a.file)];
const resources=[];
for(const file of files){
 const expected=await readFile(dir+'/'+file);
 const response=await fetch('http://localhost:4222/'+file);
 if(!response.ok)throw Error('HTTP '+response.status+' '+file);
 const bytes=Buffer.from(await response.arrayBuffer());
 const hash=b=>createHash('sha256').update(b).digest('hex');
 const entry={file,bytes:bytes.length,sha256:hash(bytes),expectedSha256:hash(expected),matched:hash(bytes)===hash(expected)};
 resources.push(entry);
 if(!entry.matched)throw Error('Live bytes differ: '+file);
}
const report={variant,origin:'http://localhost:4222/',source:current,template:build.template,mode:build.webMode,resources,passed:true,scope:'Current source/build/live metadata and every 30 public delivery resources. Same origin retained; no user save file or browser storage changes.'};
await writeFile(root+'/docs/qa-godot-native/completion-sheet-20261119/delivery.json',JSON.stringify(report,null,2));
console.log(JSON.stringify({source:current,resources:resources.length,passed:true}));



