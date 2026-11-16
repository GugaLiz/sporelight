import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,readdir,readFile,writeFile,copyFile,symlink} from 'node:fs/promises';
import {join,resolve} from 'node:path';

// GPU QA renders explicit SubViewports. Give only its unused host window an
// offscreen, non-focusable configuration; never change the playable project.
const root=process.cwd();
const option=key=>process.argv.find(v=>v.startsWith('--'+key+'='))?.slice(key.length+3);
const script=option('script'),output=option('output'),source=option('source-sha');
if(!script?.startsWith('res://tests/')||!output||!source)throw Error('Required: --script=res://tests/... --output=... --source-sha=...');
const tmp=join(root,'.tmp');
await mkdir(tmp,{recursive:true});
const host=await mkdtemp(join(tmp,'native-gpu-host-'));
for(const entry of await readdir(join(root,'godot'),{withFileTypes:true})){
 if(entry.name==='build'||entry.name==='project.godot')continue;
 const original=join(root,'godot',entry.name),target=join(host,entry.name);
 if(entry.isDirectory())await symlink(original,target,'junction');
 else await copyFile(original,target);
}
const project=await readFile(join(root,'godot/project.godot'),'utf8');
await writeFile(join(host,'project.godot'),project.replace('[display]','[display]\nwindow/size/no_focus=true'));
const out=resolve(output);
await mkdir(out,{recursive:true});
await writeFile(join(out,'gpu-host.json'),JSON.stringify({host,script,source,rendering:'gl_compatibility',window:{noFocus:true,position:[-32000,-32000],size:[64,64]},scope:'Only host window differs. Test scenes render into explicit SubViewports; native GPU, not headless.'},null,2)+'\n');
const engine=process.env.GODOT_BIN??join(process.env.USERPROFILE,'.cache/sporelight-godot/4.7.2/engine/Godot_v4.7.2-stable_win64_console.exe');
const args=['--path',host,'--rendering-method','gl_compatibility','--audio-driver','Dummy','--windowed','--position','-32000,-32000','--resolution','64x64','--script',script,'--','--output='+out,'--source-sha='+source];
const child=spawn(engine,args,{cwd:root,windowsHide:true,stdio:['ignore','pipe','pipe']});
let stdout='',stderr='';
child.stdout.on('data',bytes=>{stdout+=bytes;process.stdout.write(bytes);});
child.stderr.on('data',bytes=>{stderr+=bytes;process.stderr.write(bytes);});
child.on('error',error=>{throw error;});
child.on('close',async code=>{
 await writeFile(join(out,'stdout.log'),stdout);
 await writeFile(join(out,'stderr.log'),stderr);
 process.exitCode=code??1;
});
