import{readFile,writeFile,access}from'node:fs/promises';
import{resolve,relative,dirname,sep}from'node:path';
import{fileURLToPath}from'node:url';

// Synchronize authored generation provenance and explicit frame selections.
// No image generation, resampling, playable-resource activation or source edit.
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const option=(key,fallback)=>process.argv.find(v=>v.startsWith('--'+key+'='))?.slice(key.length+3)??fallback;
const configFile=resolve(root,option('config','assets/images/full-asset-redraw-20261116/config.json'));
const jobsFile=resolve(root,option('jobs','assets/images/full-asset-redraw-20261116/generated-jobs.json'));
const config=JSON.parse((await readFile(configFile,'utf8')).replace(/^\uFEFF/,''));
const data=JSON.parse((await readFile(jobsFile,'utf8')).replace(/^\uFEFF/,''));
const jobs=Array.isArray(data)?data:data.jobs;
if(!Array.isArray(jobs)||!Array.isArray(config.entries))throw Error('Expected jobs and configured entries arrays');
const resolveEntry=id=>config.entries.find(e=>e.id===id||e.aliases?.includes(id));
const summary={updated:[],unmatchedJobs:[],pendingMasters:[]};
const assigned=new Map();
for(const job of jobs){
 const outputs=job.outputs??[{id:job.id,master_rect:job.master_rect,cell:job.cell,registration:job.registration}];
 let matched=false;
 for(const output of outputs){
  const entry=resolveEntry(output.id);if(!entry)continue;matched=true;
  const master=output.master??job.master??entry.master;
  const absolute=resolve(root,master),rel=relative(root,absolute);
  if(rel==='..'||rel.startsWith('..'+sep)||/^[a-z]:/i.test(rel))throw Error('Master must already be copied into the workspace: '+master);
  const selection={master,master_rect:output.master_rect,cell:output.cell};
  if(assigned.has(entry.id)&&JSON.stringify(assigned.get(entry.id))!==JSON.stringify(selection))throw Error('One deduplicated source was assigned conflicting sheet cells: '+entry.id);
  assigned.set(entry.id,selection);
  const previousMaster=entry.master;
  const targets=config.entries.filter(e=>e.id===entry.id||(!output.master_rect&&!output.cell&&e.master===previousMaster));
  for(const target of targets){
   target.master=master;target.generation_id=job.generation_id??job.generationId??null;
   target.prompt_record=relative(root,jobsFile).split(sep).join('/')+'#'+job.id;
   if(output.master_rect){target.master_rect=output.master_rect;delete target.cell;}
   if(output.cell){target.cell=output.cell;delete target.master_rect;}
   if(output.registration){target.registration=output.registration;target.registration_locked=true;}
   if(!summary.updated.includes(target.id))summary.updated.push(target.id);
  }
 }
 if(!matched)summary.unmatchedJobs.push(job.id);
}
for(const entry of config.entries)try{await access(resolve(root,entry.master));}catch{summary.pendingMasters.push(entry.id);}
await writeFile(configFile,JSON.stringify(config,null,2)+'\n');
console.log(JSON.stringify(summary));
