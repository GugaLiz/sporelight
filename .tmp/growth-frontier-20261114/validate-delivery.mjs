import {readFile,writeFile,readdir} from 'node:fs/promises';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {sourceDigest} from '../../tools/godot-migration/source-digest.mjs';

const root=process.cwd();
const variant='growth-frontier-20261114-release';
const qa=join(root,'docs/qa-godot-native/growth-frontier-20261114');
const build=join(root,'godot/build',variant);
const json=async path=>JSON.parse(await readFile(path,'utf8'));
const cpu=await json(join(qa,'cpu-final/checks.json'));
const gpu=await json(join(qa,'gpu-final-sequential/checks.json'));
const lower=await json(join(root,'docs/qa-godot-native/frontier-growth-20261114/lower-route-gpu/checks.json'));
const metadata=await json(join(build,'build.json'));
const served=await (await fetch('http://localhost:4222/__build.json')).json();
const source=await sourceDigest(root);
const suites=cpu.results.map(result=>{
 const lines=result.stdout.trim().split(/\r?\n/);
 const data=lines.reverse().map(line=>{try{return JSON.parse(line);}catch{return null;}}).find(value=>value&&typeof value.checks==='number');
 return {label:result.label,passed:result.passed,checks:data?.checks??0};
});
const walk=async(directory,prefix='')=>{
 const files=[];
 for(const entry of await readdir(directory,{withFileTypes:true})){
  const relative=prefix+entry.name;
  if(entry.isDirectory())files.push(...await walk(join(directory,entry.name),relative+'/'));
  else files.push(relative);
 }
 return files;
};
const assets=[];
for(const file of await walk(build)){
 const response=await fetch('http://localhost:4222/'+file);
 const bytes=Buffer.from(await response.arrayBuffer());
 const hash=data=>createHash('sha256').update(data).digest('hex');
 assets.push({file,status:response.status,sha256:hash(bytes),match:hash(bytes)===hash(await readFile(join(build,file))),coop:response.headers.get('cross-origin-opener-policy'),coep:response.headers.get('cross-origin-embedder-policy')});
}
const stable=cpu.stable&&gpu.sourceFilesStable&&lower.sourceFilesStable&&[cpu.source.sha256,gpu.sourceSha256,lower.sourceSha256,metadata.source.sha256,served.source.sha256].every(sha=>sha===source.sha256);
const passed=stable&&cpu.passed&&gpu.passed&&lower.passed&&assets.every(a=>a.status===200&&a.match&&a.coop==='same-origin'&&a.coep==='require-corp');
const report={variant,url:'http://localhost:4222/',serverPid:Number(process.argv[2]),source,stable,passed,cpuChecks:suites.reduce((sum,s)=>sum+s.checks,0),cpuSuites:suites,gpuChecks:gpu.checks,gpuImages:gpu.images.length,lowerGpu:{passed:lower.passed,checks:lower.checks,images:lower.images.length},routes:gpu.routes,assets,scope:'Native GPU actual body travel and E/menu/scene mouse/touch input. HTTP artifact delivery verified; no browser playthrough, Web performance, audio or user aesthetic approval claim.'};
await writeFile(join(qa,'delivery.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({...report,assets:assets.length,cpuSuites:suites},null,2));
if(!passed)process.exitCode=1;
