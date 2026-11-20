import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {sourceDigest} from '../../../tools/godot-migration/source-digest.mjs';
const root=process.cwd(),variant='home-night-20261118',origin='http://localhost:4222';
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const build=JSON.parse(await readFile(resolve(root,'godot/build',variant,'build.json'),'utf8'));
const source=await sourceDigest(root);
const liveBuild=await fetch(origin+'/__build.json').then(r=>r.json());
const files=[...build.browserAssets.map(row=>row.file),'index.html','index.js','index.wasm','index.pck'];
const resources=[];
for(const file of files){
 const local=await readFile(resolve(root,'godot/build',variant,file));
 const response=await fetch(origin+'/'+file);
 const bytes=Buffer.from(await response.arrayBuffer());
 resources.push({file,status:response.status,bytes:bytes.length,sha256:hash(bytes),match:response.ok&&hash(local)===hash(bytes),contentType:response.headers.get('content-type')});
}
const result={variant,origin,source,buildSource:build.source,liveBuildSource:liveBuild.source,stable:source.sha256===build.source.sha256&&source.sha256===liveBuild.source.sha256,resources,passed:resources.every(r=>r.match)&&source.sha256===build.source.sha256&&source.sha256===liveBuild.source.sha256};
await writeFile(new URL('delivery.json',import.meta.url),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({passed:result.passed,stable:result.stable,source,resources:resources.length}));
if(!result.passed)process.exitCode=1;
