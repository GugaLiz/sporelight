import {spawn} from 'node:child_process';
import {readFile,writeFile,mkdir,access} from 'node:fs/promises';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {sourceDigest} from './source-digest.mjs';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const arg=(key,fallback)=>process.argv.find(v=>v.startsWith('--'+key+'='))?.slice(key.length+3)??fallback;
const engine=arg('godot',process.env.GODOT_BIN??join(process.env.USERPROFILE??'','.cache/sporelight-godot/4.7.2/engine/Godot_v4.7.2-stable_win64_console.exe'));
const output=resolve(root,arg('output','docs/qa-godot-migration'));
const manifest=join(output,'reference/manifest.json');
await access(engine);
await mkdir(output,{recursive:true});
const results=[];
let initialSource=null;
async function run(label,args){
 const started=Date.now();
 const result=await new Promise((done,reject)=>{
  const child=spawn(engine,args,{cwd:root,windowsHide:true,stdio:['ignore','pipe','pipe']});
  let stdout='',stderr='';
  child.stdout.on('data',data=>stdout+=data);
  child.stderr.on('data',data=>stderr+=data);
  const timer=setTimeout(()=>child.kill(),label==='import'?180000:120000);
  child.once('error',reject);
  child.once('close',code=>{clearTimeout(timer);done({label,code,elapsedMs:Date.now()-started,stdout,stderr});});
 });
 results.push(result);
 await writeFile(join(output,label+'.log'),result.stdout+result.stderr);
 const scriptErrors=/SCRIPT ERROR:|Parse Error:|Failed to load script|ERROR:/.test(result.stdout+result.stderr);
 console.log(JSON.stringify({label,code:result.code,scriptErrors,elapsedMs:result.elapsedMs,tail:(result.stdout+result.stderr).split(/\r?\n/).filter(Boolean).slice(-10)}));
 if(result.code!==0||scriptErrors)throw Error(label+' failed; inspect '+join(output,label+'.log'));
}
try{
 await run('version',['--version']);
 await run('import',['--headless','--path',join(root,'godot'),'--editor','--import']);
 initialSource=await sourceDigest(root);
 for(const [label,file] of [['rules','rule_reference.gd'],['normalization','rule_normalize.gd'],['query-scope','rule_query_scope.gd'],['services','service_save_test.gd'],['hud','service_hud_test.gd'],['visual-contract','visual_contract_test.gd'],['visual-scene','visual_scene_test.gd'],['visual-dynamic','visual_dynamic_test.gd'],['visual-walk','visual_walk_transition_test.gd'],['visual-cache','visual_draw_cache_test.gd'],['visual-pond','visual_pond_geometry_test.gd'],['session','session_test.gd'],['input','rule_input.gd'],['controller','rule_integration.gd'],['application','rule_application.gd']]){
  await run(label,['--headless','--path',join(root,'godot'),'--script','res://tests/'+file]);
 }
 try{await access(manifest);await run('visual-reference',['--headless','--path',join(root,'godot'),'--script','res://tests/visual_reference_test.gd','--','--manifest='+manifest]);}catch(error){if(error.code!=='ENOENT')throw error;}
 await run('application-smoke',['--headless','--path',join(root,'godot'),'--quit-after','12']);
}catch(error){process.exitCode=1;console.error(error.message);}
finally{
 const toolchain=JSON.parse(await readFile(join(root,'godot/toolchain.json'),'utf8'));
 const source=await sourceDigest(root);
 if(initialSource&&initialSource.sha256!==source.sha256){process.exitCode=1;console.error('Runtime sources changed during checks; results are not a stable-source verification.');}
 await writeFile(join(output,'checks.json'),JSON.stringify({toolchain,source,initialSource,results,passed:!process.exitCode},null,2)+'\n');
}
