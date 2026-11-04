import {build} from 'esbuild';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const arg=(name,fallback)=>process.argv.find(v=>v.startsWith(`--${name}=`))?.slice(name.length+3)??fallback;
const output=resolve(arg('output',resolve(root,'godot/tests/fixtures/reference.json')));
const bundle=await build({stdin:{contents:"export {GardenWorld} from './src/app/garden2/world';export {GARDEN_LEVELS} from './src/app/garden2/levels';export {GARDEN_SOLUTIONS} from './tests/garden2Solutions';",resolveDir:root},bundle:true,platform:'node',format:'esm',write:false});
const {GardenWorld,GARDEN_LEVELS,GARDEN_SOLUTIONS}=await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`);
const clone=v=>JSON.parse(JSON.stringify(v));
const sourceFiles=['src/app/garden2/world.ts','src/app/garden2/types.ts','src/app/garden2/levels.ts','src/app/garden2/mirrorGuide.ts','tests/garden2Solutions.ts'];
const sources=Object.fromEntries(await Promise.all(sourceFiles.map(async path=>[path,createHash('sha256').update(await readFile(resolve(root,path))).digest('hex')])));
const observe=w=>clone({snapshot:w.snapshot(),tiles:w.tiles,commands:w.commands(),ready:w.ready(),together:w.together,budget:w.budget,rays:w.rays(),lampRay:w.lampRay(),hint:w.hint(),canUndo:w.canUndo});
const cases=[];
function scenario(name,id,run,saved){
 let w=new GardenWorld(id,saved);const entry={name,levelId:id,...(saved?{saved}:{}),initial:observe(w),steps:[]};
 const apply=(kind,value='',internal=false)=>{let result;if(kind==='move')result=w.move(value);else if(kind==='act')result=w.act(value,internal);else if(kind==='undo')result={ok:w.undo()};else if(kind==='restore'){w=new GardenWorld(id,w.snapshot());result={ok:true};}else throw Error(kind);entry.steps.push({command:{kind,value,...(internal?{internal}: {})},result,...observe(w)});return result;};
 const go=tile=>{const route=w.pathTo(tile);if(!route)throw Error(`${name}: no path to ${tile}`);for(const at of route){const r=apply('move',at);if(!r.ok)throw Error(`${name}: ${r.message}`);}};
 const act=value=>{const r=apply('act',value);if(!r.ok)throw Error(`${name}: ${value}: ${r.message}`);};
 run({get world(){return w;},apply,go,act});cases.push(entry);
}
function solve(api,id){for(const step of GARDEN_SOLUTIONS[id]){if(step.startsWith('!'))api.act(step.slice(1));else api.go(step);}}
for(const level of GARDEN_LEVELS){scenario(`authored/${level.id}`,level.id,api=>solve(api,level.id));
 scenario(`rejection/${level.id}`,level.id,api=>{api.apply('move','missing-tile');api.apply('act','missing-command');api.apply('act','repair');api.apply('undo');api.apply('restore');});
 scenario(`all-collections/${level.id}`,level.id,api=>{const collect=()=>{const origin=api.world.state.actors[api.world.actor];for(const c of api.world.level.collectibles)if(!api.world.state.collected.includes(c.id)&&api.world.pathTo(c.tile)){api.go(c.tile);api.go(origin);}};collect();for(const step of GARDEN_SOLUTIONS[level.id]){if(step==='!repair')collect();if(step.startsWith('!'))api.act(step.slice(1));else api.go(step);}if(api.world.state.collected.length!==level.total)throw Error(`Collection budget ${level.id}`);});
}
scenario('root/alternate-route','1-2',api=>{api.go('f:1:1');for(const dir of ['down','right','right','up'])api.act(`grow:root:${dir}`);api.go('f:4:1');api.act('repair');api.apply('restore');});
scenario('root/occupied-retraction','1-2',api=>{api.go('f:1:1');api.act('grow:root:up');api.go('g:root:1:0');api.apply('act','retract:root');api.apply('undo');api.apply('undo');api.apply('restore');});
{
 const first=new GardenWorld('1-2');for(const at of first.pathTo('f:1:1'))first.move(at);
 const queue=[first.snapshot()],seen=new Set();let solved=0;
 for(let i=0;i<queue.length;i++){const w=new GardenWorld('1-2',queue[i]),key=JSON.stringify(w.state.growth.root);if(seen.has(key))continue;seen.add(key);if(w.connected())solved++;
  for(const c of w.commands().filter(c=>c.id.startsWith('grow:'))){const n=new GardenWorld('1-2',w.snapshot());if(!n.act(c.id).ok)throw Error('Offered root command rejected');queue.push(n.snapshot());}
  scenario(`root/branch-${seen.size}`,'1-2',api=>{while(api.world.state.growth.root.length)api.act('retract:root');if(api.world.budget!==4)throw Error('Root budget did not recover');api.apply('restore');},w.snapshot());
 }if(solved!==2)throw Error(`Unexpected complete root routes: ${solved}`);
}
scenario('module/off-centre-passenger','1-3',api=>{api.go('m:garden:-1:0');api.act('turn:garden');api.apply('undo');api.act('turn:garden');api.apply('restore');});
scenario('dew/drop-undo-reload','2-1',api=>{api.go('f:0:4');api.act('take:dew');api.act('drop:dew:f:0:4');api.apply('undo');api.apply('undo');api.act('take:dew');api.apply('restore');});
const permutations=values=>values.length?values.flatMap((v,i)=>permutations(values.filter((_,n)=>n!==i)).map(rest=>[v,...rest])):[[]];
for(const song of permutations(['turn','rise','rest']))scenario(`song/${song.join('-')}`,'2-3',api=>{api.go('m:stage:0:0');api.act('switch');api.go('f:-4:0');for(let i=0;i<3;i++){let j=api.world.state.song.indexOf(song[i]);while(j>i){api.act(`swap:${j-1}`);j--;}}for(let i=0;i<3;i++)api.act('beat');api.act('resetSong');api.apply('restore');});
scenario('song/playing-passenger-reload','2-3',api=>{api.go('m:stage:0:0');api.act('switch');api.act('swap:0');api.act('play');api.apply('act','beat',true);api.act('switch');api.apply('restore');api.act('play');api.act('resetSong');});
for(const mode of [0,1])scenario(`shadow/retain-${mode}`,'3-2',api=>{for(const step of GARDEN_SOLUTIONS['3-2']){if(step==='f:-1:1')break;if(step.startsWith('!'))api.act(step.slice(1));else api.go(step);}if(mode){api.go('f:-1:0');api.act('valve:mode');}api.go('f:-1:1');api.act('freeze');api.go('f:-1:0');api.act('valve:mode');api.go('f:3:4');api.act('repair');api.apply('restore');});
scenario('shadow/retained-geometry','3-2',api=>{for(const step of GARDEN_SOLUTIONS['3-2']){if(step==='f:-1:1')break;if(step.startsWith('!'))api.act(step.slice(1));else api.go(step);}api.go('f:-1:1');api.act('freeze');api.go('f:-1:0');api.act('valve:mode');api.go('f:0:0');api.act('take:sunPost');api.apply('restore');});
scenario('shadow/occupied-floor-protection','3-2',api=>{for(const step of GARDEN_SOLUTIONS['3-2']){if(step==='f:-1:1')break;if(step.startsWith('!'))api.act(step.slice(1));else api.go(step);}api.go('f:-1:1');api.act('freeze');api.go('f:-1:0');api.act('valve:mode');api.go('shadow:moon:2');api.act('switch');api.go('f:-1:0');api.apply('act','valve:mode');api.apply('undo');api.apply('restore');});
scenario('final/current-light-required','3-4',api=>{for(const step of GARDEN_SOLUTIONS['3-4']){if(step==='!repair')break;if(step.startsWith('!'))api.act(step.slice(1));else api.go(step);}api.go('f:1:-4');api.go('m:lift:0:0');api.act('valve:lift');api.go('m:light:0:0');api.act('turn:light');if(api.world.ready())throw Error('Historical star incorrectly satisfies current light');api.apply('restore');});
scenario('module/placed-mirror-rides','3-4',api=>{for(const step of GARDEN_SOLUTIONS['3-4']){if(step==='m:lift:0:0')break;if(step.startsWith('!'))api.act(step.slice(1));else api.go(step);}api.go('m:inner:-1:0');api.act('drop:mirror:m:inner:-1:0');api.act('turn:inner');api.apply('undo');api.apply('restore');});
scenario('completed/walk-observe-no-rebuild','1-2',api=>{solve(api,'1-2');api.go('f:5:1');api.apply('act','grow:root:right');for(const c of api.world.commands().filter(c=>c.id.startsWith('observe:')))api.act(c.id);api.apply('restore');});
for(let n=0;n<4;n++)scenario(`water/recover-${n}`,'3-3',api=>{api.go('m:water:0:0');for(let i=0;i<n;i++)api.act('turn:water');while(api.world.state.turns.water!==0)api.act('turn:water');solve(api,'3-3');});
const saves=[];
for(const level of GARDEN_LEVELS){const initial=new GardenWorld(level.id).snapshot();const variants=[['initial',initial],['bad-version',{...initial,designVersion:99}],['bad-position',{...initial,actors:{luvie:'void',buddy:'void'}}],['bad-flags',{...initial,flags:[1]}],['missing-growth',Object.fromEntries(Object.entries(initial).filter(([key])=>key!=='growth'))],['collection-filter',{...initial,collected:['spore-0','spore-0','not-a-reward']}],['bad-trial',{...initial,trial:'{"designVersion":2,"levelId":"other"}'}],['json-numeric-enums',{...initial,water:1,mode:1,frozen:0,beat:2}],['booleans-are-not-numbers',{...initial,water:true,mode:true,frozen:false,beat:true}],['numbers-are-not-booleans',{...initial,follow:1,playing:1,completed:1}]];for(const [name,input]of variants)saves.push({name:`${level.id}/${name}`,levelId:level.id,input,expected:new GardenWorld(level.id,input).snapshot()});}
const head=execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim();
const payload={format:'sporelight.rule-reference',version:1,referenceCommit:head,sources,cases};
await mkdir(dirname(output),{recursive:true});
await mkdir(resolve(root,'godot/content'),{recursive:true});
await writeFile(resolve(root,'godot/content/levels.json'),JSON.stringify({version:1,referenceCommit:head,levels:GARDEN_LEVELS},null,2)+'\n');
await writeFile(output,JSON.stringify(payload)+'\n');
await writeFile(resolve(dirname(output),'save-cases.json'),JSON.stringify({version:1,cases:saves})+'\n');
console.log(JSON.stringify({output,cases:cases.length,commands:cases.reduce((n,c)=>n+c.steps.length,0),saveCases:saves.length,levels:GARDEN_LEVELS.length,referenceCommit:head}));
