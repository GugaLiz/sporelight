import {readFile,writeFile,readdir} from 'node:fs/promises';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {sourceDigest} from '../../tools/godot-migration/source-digest.mjs';
const root=process.cwd(),variant='symbiosis-return-20261115-release';
const qa=join(root,'docs/qa-godot-native/symbiosis-direct-route-20261115');
const build=join(root,'godot/build',variant);
const json=async path=>JSON.parse(await readFile(path,'utf8'));
const cpu=await json(join(qa,'cpu-final/checks.json'));
const gpu=await json(join(qa,'gpu-final/checks.json'));
const metadata=await json(join(build,'build.json'));
const served=await (await fetch('http://localhost:4222/__build.json')).json();
const source=await sourceDigest(root);
const suites=cpu.results.map(r=>{
 const result=r.stdout.trim().split(/\r?\n/).reverse().map(line=>{try{return JSON.parse(line);}catch{return null;}}).find(value=>value&&typeof value.checks==='number');
 return {label:r.label,passed:r.passed,checks:result?.checks??0};
});
async function walk(dir,prefix=''){
 const files=[];
 for(const entry of await readdir(dir,{withFileTypes:true})){
  if(entry.isDirectory())files.push(...await walk(join(dir,entry.name),prefix+entry.name+'/'));
  else files.push(prefix+entry.name);
 }
 return files;
}
const hash=data=>createHash('sha256').update(data).digest('hex'),assets=[];
for(const file of await walk(build)){
 const response=await fetch('http://localhost:4222/'+file);
 const sha256=hash(Buffer.from(await response.arrayBuffer()));
 assets.push({file,status:response.status,sha256,match:sha256===hash(await readFile(join(build,file))),coop:response.headers.get('cross-origin-opener-policy'),coep:response.headers.get('cross-origin-embedder-policy')});
}
const stable=cpu.stable&&gpu.sourceFilesStable&&[cpu.source.sha256,gpu.sourceSha256,metadata.source.sha256,served.source.sha256].every(value=>value===source.sha256);
const passed=stable&&cpu.passed&&gpu.passed&&assets.every(a=>a.status===200&&a.match&&a.coop==='same-origin'&&a.coep==='require-corp');
const report={variant,url:'http://localhost:4222/',serverPid:Number(process.argv[2]),source,stable,passed,cpuChecks:suites.reduce((n,s)=>n+s.checks,0),cpuSuites:suites,gpuChecks:gpu.checks,gpuImages:gpu.images.length,routes:gpu.routes,preparedBoundaries:gpu.preparedBoundaries,assets,scope:'New route actual travel at two sizes and historical route actual travel. Water2/3 use explicit prepared legal saves followed by real layered walking and rotation. HTTP source/hash/header validation; no browser playthrough, performance or audio claim.'};
await writeFile(join(qa,'delivery.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({...report,assets:assets.length},null,2));
if(!passed)process.exitCode=1;
