import {spawn} from 'node:child_process';
import {mkdir,writeFile,readFile,copyFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {sourceDigest} from './source-digest.mjs';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const engine=process.env.GODOT_BIN??join(process.env.USERPROFILE??'','.cache/sporelight-godot/4.7.2/engine/Godot_v4.7.2-stable_win64_console.exe');
const release=process.argv.includes('--release');
const optimized=release&&!process.argv.includes('--official-web');
const option=(key,fallback)=>process.argv.find(value=>value.startsWith('--'+key+'='))?.slice(key.length+3)??fallback;
let template={kind:'official',target:release?'release':'debug'};
if(optimized){
 const manifestPath=join(root,'docs/qa-godot-native/custom-web-template/release-build.json');
 let manifest;
 try{manifest=JSON.parse(await readFile(manifestPath,'utf8'));}
 catch{throw Error('Optimized Web template is missing. Run python tools/godot-migration/build-web-template.py, or explicitly use --official-web for the original template.');}
 const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
 const patchSha=sha(await readFile(join(root,'tools/godot-migration/patches/godot-4.7.2-web-scene-demand.patch')));
 if(manifest.status!=='built'||manifest.target!=='release'||manifest.sourceCommit!=='ed1daf0bf001b61586d9930840f2f1394092c079'||manifest.patchSha256!==patchSha)throw Error('Optimized Web template provenance is incomplete or differs from the current engine patch; rebuild it first.');
 const archive=await readFile(manifest.template);
 if(sha(archive)!==manifest.templateSha256)throw Error('Optimized Web template checksum mismatch.');
 const directory=join(root,'.cache/godot-web-templates');
 await mkdir(directory,{recursive:true});
 await writeFile(join(directory,'web_release.zip'),archive);
 template={kind:'scene-demand',target:'release',sha256:manifest.templateSha256,sourceCommit:manifest.sourceCommit,patchSha256:patchSha,flags:manifest.flags};
}
const build=join(root,'godot/build');
const webDirectory=option('variant',release?'web-release':'web');
if(!/^[a-z][a-z0-9-]{0,48}$/.test(webDirectory))throw Error('Invalid build variant');
await mkdir(join(build,webDirectory),{recursive:true});
await mkdir(join(build,'windows'),{recursive:true});
await writeFile(join(build,'.gdignore'),'');
const operations=[['import',['--editor','--import']],['Web',[release?'--export-release':'--export-debug',optimized?'Web Optimized':'Web','build/'+webDirectory+'/index.html']]];
if(!process.argv.includes('--web-only'))operations.push(['Windows',['--export-release','Windows','build/windows/Sporelight.exe']]);
const results=[];
const browserAssets=[];
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
 if(name==='Web'){
  // Bootstrap images must be public files: the PCK is not available while downloading.
  const directory=join(build,webDirectory,'loader');
  await mkdir(directory,{recursive:true});
  for(const file of ['bg.webp','logo.png','hero.png','orb.png']){
   const sourceFile=join(root,'godot/web/loader',file);
   const bytes=await readFile(sourceFile);
   await copyFile(sourceFile,join(directory,file));
   browserAssets.push({file:'loader/'+file,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')});
  }
 }
 results.push({name,code:result.code});
 console.log(name+' passed');
}
const lock=JSON.parse(await readFile(join(root,'godot/toolchain.json'),'utf8'));
const source=await sourceDigest(root);
if(initialSource.sha256!==source.sha256)throw Error('Runtime sources changed during export; rebuild before serving or validating this candidate.');
const metadata=JSON.stringify({engine:lock.version,template,webMode:release?'release':'debug',source,initialSource,results,browserAssets},null,2)+'\n';
await writeFile(join(build,webDirectory,'build.json'),metadata);
await writeFile(join(build,'build.json'),metadata);
console.log('Web: godot/build/'+webDirectory+'/index.html');
if(!process.argv.includes('--web-only'))console.log('Windows: godot/build/windows/Sporelight.exe + Sporelight.pck');

