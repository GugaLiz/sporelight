import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const require=createRequire(import.meta.url),ts=require('typescript');
const compile=text=>ts.transpileModule(text,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText;
const dataUrl='data:text/javascript;base64,'+Buffer.from(compile(await readFile(resolve(root,'src/app/cloud/data.ts'),'utf8'))).toString('base64');
const data=await import(dataUrl);
const source=compile(await readFile(resolve(root,'src/app/cloud/model.ts'),'utf8')).replaceAll("from './data'","from '"+dataUrl+"'");
const {CloudModel}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
const key=s=>JSON.stringify({...s,found:[...s.found].sort()});
const levels=[];
for(const level of data.CLOUD_LEVELS){
 const initial=new CloudModel(level.id).snapshot(),queue=[{state:initial,parent:-1,action:null}],seen=new Set([key(initial)]);
 let end=-1;
 for(let i=0;i<queue.length;i++){
  const node=queue[i],model=new CloudModel(level.id,node.state);
  if(model.state.repaired&&model.state.found.length===2){end=i;break;}
  const choices=[...model.neighbors(model.state.tile).map(t=>({kind:'move',value:t.id})),...model.actions().map(a=>({kind:'act',value:a.id}))];
  for(const action of choices){
   const candidate=new CloudModel(level.id,node.state);
   const accepted=action.kind==='move'?candidate.move(action.value):candidate.act(action.value).ok;
   if(!accepted)continue;
   const state=candidate.snapshot(),stamp=key(state);
   if(!seen.has(stamp)){seen.add(stamp);queue.push({state,parent:i,action});}
  }
 }
 if(end<0)throw Error('No complete route for '+level.id);
 const steps=[];
 for(let i=end;queue[i].parent>=0;i=queue[i].parent)steps.push({command:queue[i].action,snapshot:queue[i].state});
 steps.reverse();
 levels.push({id:level.id,initial,steps});
 console.log(JSON.stringify({id:level.id,states:queue.length,steps:steps.length,found:queue[end].state.found}));
}
const output=resolve(root,'godot/tests/fixtures/cloud-reference.json');
await mkdir(dirname(output),{recursive:true});
await writeFile(output,JSON.stringify({source:'Original TypeScript CloudModel; BFS full discovery and repair',levels},null,2)+'\n');

