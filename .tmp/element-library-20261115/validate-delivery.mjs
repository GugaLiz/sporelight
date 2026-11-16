import {readFile,writeFile,readdir} from 'node:fs/promises';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {sourceDigest} from '../../tools/godot-migration/source-digest.mjs';
const root=process.cwd(),variant='element-library-20261115-release';
const qa=join(root,'docs/qa-godot-native/element-library-20261115');
const build=join(root,'godot/build',variant);
const json=async p=>JSON.parse(await readFile(p,'utf8'));
const hash=b=>createHash('sha256').update(b).digest('hex');
const source=await sourceDigest(root),cpu=await json(join(qa,'cpu-release/checks.json'));
const routes=await json(join(qa,'routes-release/checks.json'));
const gpu=await json(join(qa,'current/report.json'));
const metadata=await json(join(build,'build.json'));
const served=await (await fetch('http://localhost:4222/__build.json')).json();
const compare=await json(join(qa,'source-comparison.json'));
const validated=await json(join(qa,'validated-source-manifest.json'));
const editorOnly=new Set(['elements/element_catalog.gd','elements/element_document.gd']);
const sourceDelta=[];
for(const [path,sha] of validated.entries){
 if(hash(await readFile(join(root,'godot',path)))!==sha)sourceDelta.push(path);
}
// These two export/validation adapters have no callers in the running game.
// All gameplay/render bytes were tested at the validated source; only the
// editor document lifecycle fix was subsequently changed and retested.
const productionCallers=[];
for(const [path] of validated.entries){
 if(!path.endsWith('.gd')||editorOnly.has(path))continue;
 const text=await readFile(join(root,'godot',path),'utf8');
 if(/element_catalog\.gd|element_document\.gd/.test(text))productionCallers.push(path);
}
const runtimeSourcesUnchanged=source.files===validated.source.files&&sourceDelta.every(p=>editorOnly.has(p))&&productionCallers.length===0;
const checksFrom=results=>results.map(r=>{
 const s=r.stdout.trim().split(/\r?\n/).reverse().map(x=>{try{return JSON.parse(x)}catch{return null}}).find(x=>x&&typeof x.checks==='number');
 return {label:r.label,passed:r.passed,checks:s?.checks??0,summary:s};
});
const gpuSources=[];
for(const [path,expected] of Object.entries(gpu.finalSources))gpuSources.push({path,match:hash(await readFile(join(root,'godot',path.replace('res://',''))))===expected});
const catalog=[];
for(const name of ['catalog-final','inventory-final']){
 const log=await readFile(join(qa,name+'.log'),'utf8');
 const result=log.trim().split(/\r?\n/).reverse().map(x=>{try{return JSON.parse(x)}catch{return null}}).find(x=>x?.suite);
 catalog.push({name,...result,clean:!log.includes('ERROR:')});
}
async function walk(dir,prefix=''){
 const files=[];
 for(const entry of await readdir(dir,{withFileTypes:true})){
  if(entry.isDirectory())files.push(...await walk(join(dir,entry.name),prefix+entry.name+'/'));
  else files.push(prefix+entry.name);
 }
 return files;
}
const assets=[];
for(const file of await walk(build)){
 const response=await fetch('http://localhost:4222/'+file),bytes=Buffer.from(await response.arrayBuffer());
 assets.push({file,status:response.status,sha256:hash(bytes),match:hash(bytes)===hash(await readFile(join(build,file))),coop:response.headers.get('cross-origin-opener-policy'),coep:response.headers.get('cross-origin-embedder-policy')});
}
const stable=cpu.stable&&routes.stable&&gpu.sourceFilesStable&&runtimeSourcesUnchanged&&gpuSources.every(x=>x.match||editorOnly.has(x.path.replace('res://','')))&&[cpu.source.sha256,routes.source.sha256].every(x=>x===validated.source.sha256)&&[metadata.source.sha256,served.source.sha256].every(x=>x===source.sha256);
const passed=stable&&cpu.passed&&routes.passed&&gpu.passed&&catalog.every(x=>x.passed&&x.clean)&&compare.protectedUnchanged&&assets.every(x=>x.status===200&&x.match&&x.coop==='same-origin'&&x.coep==='require-corp');
const report={variant,url:'http://localhost:4222/',serverPid:Number(process.argv[2]),source,validatedRuntimeSource:validated.source,sourceDelta,runtimeSourcesUnchanged,productionCallers,stable,passed,cpu:checksFrom(cpu.results),routes:checksFrom(routes.results),catalog,gpu:{images:gpu.images.length,passed:gpu.passed,sourceFilesStable:gpu.sourceFilesStable,matchedSourceFiles:gpuSources.filter(x=>x.match).length,editorOnlyDifferences:gpuSources.filter(x=>!x.match)},protectedUnchanged:compare.protectedUnchanged,assets,scope:'Shared library refactor. Native headless physical routes, native GPU scene comparisons and HTTP delivery. After stable runtime tests only two unused editor interchange adapters changed; lifecycle/catalog tests rerun against release source. Exact byte audit proves no gameplay/render changes. Existing baseline failures remain documented separately; not Web input/audio/performance acceptance.'};
await writeFile(join(qa,'delivery.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({...report,cpu:report.cpu.map(({summary,...r})=>r),routes:report.routes.map(({summary,...r})=>r),assets:assets.length},null,2));
if(!passed)process.exitCode=1;
