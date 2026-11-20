import {readFile,readdir,mkdir,rename,cp,writeFile,stat} from 'node:fs/promises';
import {resolve,join,relative,sep} from 'node:path';
import {createHash} from 'node:crypto';
import {sourceDigest} from '../../tools/godot-migration/source-digest.mjs';
const root=process.cwd();
const candidate=resolve(root,'godot/build/full-asset-redraw-20261117-release');
const target=resolve(root,'dist');
const output=resolve(root,'output/deployment-20261117');
const backup=resolve(root,'.tmp/dist-before-deployment-20261117');
for(const path of [candidate,target,output,backup])if(!path.startsWith(root+sep))throw Error('Path outside workspace');
const build=JSON.parse(await readFile(join(candidate,'build.json'),'utf8'));
const current=await sourceDigest(root);
if(build.webMode!=='release'||build.source.sha256!==current.sha256)throw Error('Release/source mismatch');
await mkdir(output,{recursive:true});
try{await stat(backup);throw Error('Backup already exists; refusing to overwrite');}catch(error){if(error.code!=='ENOENT')throw error;}
await rename(target,backup);
await cp(candidate,target,{recursive:true});
await writeFile(join(target,'.nojekyll'),'');
const resources=[];
async function scan(dir){for(const entry of await readdir(dir,{withFileTypes:true})){const file=join(dir,entry.name);if(entry.isDirectory())await scan(file);else{const bytes=await readFile(file);resources.push({file:relative(target,file).split(sep).join('/'),bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')});}}}
await scan(target);
const html=await readFile(join(target,'index.html'),'utf8');
const references=[...html.matchAll(/(?:src|href)=["']([^"']+)["']/g),...html.matchAll(/url\(["']?([^\)"']+)["']?\)/g)].map(match=>match[1]).filter(value=>!value.startsWith('#')&&!/^(?:https?:|data:)/.test(value));
for(const ref of references){const file=resolve(target,ref.split('?')[0]);if(!file.startsWith(target+sep))throw Error('Absolute reference '+ref);await stat(file);}
const report={createdAt:new Date().toISOString(),branch:'dev',commit:'94343ab',source:current,variant:'full-asset-redraw-20261117-release',webMode:build.webMode,template:build.template,backup,files:resources.length,totalBytes:resources.reduce((sum,r)=>sum+r.bytes,0),htmlReferencesChecked:references.length,resources};
await writeFile(join(output,'dist-audit.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({...report,resources:undefined},null,2));
