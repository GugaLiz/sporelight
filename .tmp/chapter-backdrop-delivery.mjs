import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {sourceDigest} from '../tools/godot-migration/source-digest.mjs';
const root='G:/works/liuli/sporelight',variant='chapter-backdrop-20261119-final';
const origin='http://localhost:'+(process.argv[2]??'4222');
const dir=root+'/godot/build/'+variant,build=JSON.parse(await readFile(dir+'/build.json','utf8'));
const source=await sourceDigest(root),live=await(await fetch(origin+'/__build.json')).json();
if(source.sha256!==build.source.sha256||source.sha256!==live.source.sha256)throw Error('Source/build/live mismatch');
const sha=b=>createHash('sha256').update(b).digest('hex'),resources=[];
for(const file of ['index.html','index.js','index.wasm','index.pck',...build.browserAssets.map(a=>a.file)]){
 const expected=await readFile(dir+'/'+file),response=await fetch(origin+'/'+file);
 if(!response.ok)throw Error('HTTP '+response.status+' '+file);
 const data=Buffer.from(await response.arrayBuffer()),matched=sha(data)===sha(expected);
 resources.push({file,bytes:data.length,sha256:sha(data),expectedSha256:sha(expected),matched});
 if(!matched)throw Error('Mismatch '+file);
}
const result={variant,origin,source,template:build.template,webMode:build.webMode,resources,passed:true,scope:'Current source/build/live metadata and all 30 delivered resources; same origin retained, no user storage mutations.'};
await writeFile(root+'/docs/qa-godot-native/chapter-backdrop-20261119/delivery-'+(process.argv[2]??'4222')+'.json',JSON.stringify(result,null,2));
console.log(JSON.stringify({source,resources:resources.length,origin,passed:true}));





