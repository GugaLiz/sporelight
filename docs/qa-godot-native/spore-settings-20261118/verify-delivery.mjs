import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {sourceDigest} from '../../../tools/godot-migration/source-digest.mjs';
const root=process.cwd(),variant='spore-settings-20261118',origin='http://localhost:4222';
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const build=JSON.parse(await readFile(resolve(root,'godot/build',variant,'build.json'),'utf8'));
const source=await sourceDigest(root);
const liveBuild=await fetch(origin+'/__build.json').then(r=>r.json());
const resources=[];
for(const file of [...build.browserAssets.map(row=>row.file),'index.html','index.js','index.wasm','index.pck']){
 const local=await readFile(resolve(root,'godot/build',variant,file));
 const response=await fetch(origin+'/'+file),bytes=Buffer.from(await response.arrayBuffer());
 resources.push({file,status:response.status,bytes:bytes.length,sha256:hash(bytes),match:response.ok&&hash(local)===hash(bytes)});
}
const stable=source.sha256===build.source.sha256&&source.sha256===liveBuild.source.sha256;
const report={variant,origin,source,buildSource:build.source,liveBuildSource:liveBuild.source,stable,resources,passed:stable&&resources.every(r=>r.match)};
await writeFile(new URL('delivery.json',import.meta.url),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({passed:report.passed,stable,resources:resources.length,source}));
if(!report.passed)process.exitCode=1;


