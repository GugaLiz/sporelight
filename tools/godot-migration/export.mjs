import {spawn} from 'node:child_process';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {sourceDigest} from './source-digest.mjs';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const engine=process.env.GODOT_BIN??join(process.env.USERPROFILE??'','.cache/sporelight-godot/4.7.2/engine/Godot_v4.7.2-stable_win64_console.exe');
const release=process.argv.includes('--release');
const build=join(root,'godot/build');
const webDirectory=release?'web-release':'web';
await mkdir(join(build,webDirectory),{recursive:true});
await mkdir(join(build,'windows'),{recursive:true});
await writeFile(join(build,'.gdignore'),'');
const operations=[['import',['--editor','--import']],['Web',[release?'--export-release':'--export-debug','Web','build/'+webDirectory+'/index.html']],['Windows',['--export-release','Windows','build/windows/Sporelight.exe']]];
const results=[];
let initialSource=null;
for(const [name,args]of operations){
 const result=await new Promise((done,reject)=>{
  const child=spawn(engine,['--headless','--path',join(root,'godot'),...args],{cwd:root,windowsHide:true,stdio:['ignore','pipe','pipe']});
  let output='';child.stdout.on('data',chunk=>output+=chunk);child.stderr.on('data',chunk=>output+=chunk);
  child.on('error',reject);child.on('close',code=>done({name,code,output}));
 });
 await writeFile(join(build,'export-'+name.toLowerCase()+'.log'),result.output);
 if(result.code!==0||/SCRIPT ERROR:|Parse Error:|ERROR:/.test(result.output))throw Error(name+' export failed; inspect godot/build/export-'+name.toLowerCase()+'.log');
 if(name==='import')initialSource=await sourceDigest(root);
 results.push({name,code:result.code});
 console.log(name+' passed');
}
const lock=JSON.parse(await readFile(join(root,'godot/toolchain.json'),'utf8'));
const source=await sourceDigest(root);
if(initialSource.sha256!==source.sha256)throw Error('Runtime sources changed during export; rebuild before serving or validating this candidate.');
const metadata=JSON.stringify({engine:lock.version,webMode:release?'release':'debug',source,initialSource,results},null,2)+'\n';
await writeFile(join(build,webDirectory,'build.json'),metadata);
await writeFile(join(build,'build.json'),metadata);
console.log('Web: godot/build/'+webDirectory+'/index.html');
console.log('Windows: godot/build/windows/Sporelight.exe + Sporelight.pck');

