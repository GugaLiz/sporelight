import {spawn} from 'node:child_process';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {sourceDigest} from '../../../tools/godot-migration/source-digest.mjs';
const root=process.cwd();
const output=resolve(root,'docs/qa-godot-native/readability-20261118/verified-gpu');
const engine=resolve(process.env.USERPROFILE,'.cache/sporelight-godot/4.7.2/engine/Godot_v4.7.2-stable_win64_console.exe');
await mkdir(output,{recursive:true});
const before=await sourceDigest(root);
const started=Date.now();
const result=await new Promise((done,reject)=>{
  const child=spawn(engine,['--path',resolve(root,'godot'),'--rendering-method','gl_compatibility','--audio-driver','Dummy','--script','res://tests/native_readability_feedback_capture.gd','--','--output='+output],{cwd:root,windowsHide:true,stdio:['ignore','pipe','pipe']});
  let stdout='',stderr='';
  child.stdout.on('data',d=>stdout+=d);child.stderr.on('data',d=>stderr+=d);
  const timer=setTimeout(()=>child.kill(),600000);
  child.once('error',reject);child.once('close',code=>{clearTimeout(timer);done({code,stdout,stderr});});
});
await writeFile(resolve(output,'engine.log'),result.stdout+result.stderr);
const after=await sourceDigest(root);
let report=null;
try{report=JSON.parse(await readFile(resolve(output,'feedback.json'),'utf8'));}catch{}
const summary={passed:result.code===0&&report?.passed===true&&before.sha256===after.sha256&&!/SCRIPT ERROR:|Parse Error:|ERROR:/.test(result.stdout+result.stderr),code:result.code,checks:report?.checks,images:report?.images?.length,failures:report?.failures,sourceBefore:before,sourceAfter:after,elapsedMs:Date.now()-started};
await writeFile(resolve(output,'verification.json'),JSON.stringify(summary,null,2)+'\n');
console.log(JSON.stringify(summary));
if(!summary.passed)process.exitCode=1;
