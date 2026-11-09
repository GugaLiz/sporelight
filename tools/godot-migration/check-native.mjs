import {spawn} from 'node:child_process';
import {mkdir,writeFile,readdir} from 'node:fs/promises';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {sourceDigest} from './source-digest.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const option=(key,fallback)=>process.argv.find(value=>value.startsWith('--'+key+'='))?.slice(key.length+3)??fallback;
const engine=option('godot',process.env.GODOT_BIN??join(process.env.USERPROFILE??'','.cache/sporelight-godot/4.7.2/engine/Godot_v4.7.2-stable_win64_console.exe'));
const output=resolve(root,option('output','docs/qa-godot-native/headless'));
const filter=option('only','').split(',').filter(Boolean);
const results=[];
await mkdir(output,{recursive:true});
let initialSource=null,failure=null;
async function run(label,args){
 const started=Date.now();
 const result=await new Promise((done,reject)=>{
  const child=spawn(engine,args,{cwd:root,windowsHide:true,stdio:['ignore','pipe','pipe']});
  let stdout='',stderr='';
  child.stdout.on('data',d=>stdout+=d);child.stderr.on('data',d=>stderr+=d);
  const timer=setTimeout(()=>child.kill(),label.includes('route')?600000:180000);
  child.once('error',reject);child.once('close',code=>{clearTimeout(timer);done({label,code,elapsedMs:Date.now()-started,stdout,stderr});});
 });
 result.passed=result.code===0&&!/SCRIPT ERROR:|Parse Error:|Failed to load script|ERROR:/.test(result.stdout+result.stderr);
 results.push(result);await writeFile(join(output,label+'.log'),result.stdout+result.stderr);
 console.log(JSON.stringify({label,passed:result.passed,elapsedMs:result.elapsedMs,tail:(result.stdout+result.stderr).split(/\r?\n/).filter(Boolean).slice(-5)}));
 return result.passed;
}
try{
 if(!filter.length)await run('import',['--headless','--path',join(root,'godot'),'--editor','--import']);
 initialSource=await sourceDigest(root);
 const core=['rule_reference.gd','rule_normalize.gd','rule_query_scope.gd','service_save_test.gd','service_hud_test.gd','service_button_test.gd','service_modal_lifecycle_test.gd','service_home_navigation_test.gd','session_test.gd','rule_input.gd','rule_integration.gd','rule_application.gd'];
 const native=(await readdir(join(root,'godot/tests'))).filter(f=>/^native_.*test\.gd$/.test(f)).sort();
 for(const file of [...core,...native]){
  const label=file.replace(/\.gd$/,'');
  if(filter.length&&!filter.some(value=>label.includes(value)))continue;
  await run(label,['--headless','--path',join(root,'godot'),'--script','res://tests/'+file]);
 }
 if(!filter.length)await run('application-smoke',['--headless','--path',join(root,'godot'),'--quit-after','30']);
}catch(error){failure=String(error);}
const source=await sourceDigest(root);
const stable=!initialSource||initialSource.sha256===source.sha256;
const passed=!failure&&stable&&results.length>0&&results.every(result=>result.passed);
await writeFile(join(output,'checks.json'),JSON.stringify({initialSource,source,stable,passed,failure,results},null,2)+'\n');
if(!passed)process.exitCode=1;
console.log(JSON.stringify({passed,stable,suites:results.length,failed:results.filter(r=>!r.passed).map(r=>r.label),failure}));

