import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,readdir,readFile,writeFile,copyFile,symlink} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {sourceDigest} from './source-digest.mjs';

// Only the unused host window differs; explicit native SubViewports provide
// the actual scene/UI pixels. No browser, user save or project setting is edited.
const root=process.cwd();
const option=(key,fallback)=>process.argv.find(value=>value.startsWith('--'+key+'='))?.slice(key.length+3)??fallback;
const output=resolve(root,option('output','docs/qa-godot-native/full-asset-redraw-20261116/native-gpu-final'));
const script='res://tests/native_full_asset_redraw_capture.gd';
const before=await sourceDigest(root);
const supplied=option('source-sha',before.sha256);
if(supplied!==before.sha256)throw Error('Requested source hash differs from the current runtime sources');
const tmp=join(root,'.tmp');await mkdir(tmp,{recursive:true});
const host=await mkdtemp(join(tmp,'full-redraw-gpu-host-'));
for(const entry of await readdir(join(root,'godot'),{withFileTypes:true})){
 if(['build','project.godot'].includes(entry.name))continue;
 const source=join(root,'godot',entry.name),target=join(host,entry.name);
 if(entry.isDirectory())await symlink(source,target,'junction');else await copyFile(source,target);
}
const project=await readFile(join(root,'godot/project.godot'),'utf8');
await writeFile(join(host,'project.godot'),project.replace('[display]','[display]\nwindow/size/no_focus=true'));
await mkdir(output,{recursive:true});
const engine=process.env.GODOT_BIN??join(process.env.USERPROFILE,'.cache/sporelight-godot/4.7.2/engine/Godot_v4.7.2-stable_win64_console.exe');
const args=['--path',host,'--rendering-method','gl_compatibility','--rendering-driver','opengl3','--audio-driver','Dummy','--windowed','--position','-32000,-32000','--resolution','64x64','--script',script,'--','--output='+output,'--source-sha='+before.sha256];
for(const key of ['theme','bitmap'])if(option(key,''))args.push('--'+key+'='+resolve(root,option(key,'')));
await writeFile(join(output,'gpu-host.json'),JSON.stringify({host,script,source:before,renderer:'gl_compatibility/opengl3',audio:'Dummy (visual QA only)',window:{position:[-32000,-32000],size:[64,64],noFocus:true},scope:'Hidden/nonfocused offscreen host only; real native GPU SubViewports, not headless.'},null,2)+'\n');
const result=await new Promise((done,reject)=>{
 const child=spawn(engine,args,{cwd:root,windowsHide:true,stdio:['ignore','pipe','pipe']});
 let stdout='',stderr='';
 child.stdout.on('data',bytes=>{stdout+=bytes;process.stdout.write(bytes);});
 child.stderr.on('data',bytes=>{stderr+=bytes;process.stderr.write(bytes);});
 const timer=setTimeout(()=>child.kill(),420000);
 child.once('error',reject);
 child.once('close',code=>{clearTimeout(timer);done({code,stdout,stderr});});
});
await writeFile(join(output,'stdout.log'),result.stdout);
await writeFile(join(output,'stderr.log'),result.stderr);
const after=await sourceDigest(root);
const stable=before.sha256===after.sha256;
const passed=result.code===0&&stable&&!/SCRIPT ERROR:|Parse Error:|ERROR:/.test(result.stdout+result.stderr);
await writeFile(join(output,'launcher.json'),JSON.stringify({passed,stable,source:before,finalSource:after,exitCode:result.code},null,2)+'\n');
console.log(JSON.stringify({suite:'full-redraw-gpu-launcher',passed,stable,source:before.sha256,exitCode:result.code}));
if(!passed)process.exitCode=1;
