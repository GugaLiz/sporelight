import test from 'node:test';
import assert from 'node:assert/strict';
import {GardenWorld} from '../src/app/garden2/world';
import {GARDEN_LEVELS} from '../src/app/garden2/levels';
import {GARDEN_SOLUTIONS} from './garden2Solutions';
import {normalizeGardenProgress} from '../src/app/garden2/save';
import {butterflyPose} from '../src/app/garden2/gardenArt';
import {moleDialogue,MoleConversation} from '../src/app/garden2/moleDialogue';
import {terrainSteps,faceDepth,pondFootprint,TERRAIN_RISE} from '../src/app/garden2/landscape';
import {mirrorGuidance} from '../src/app/garden2/mirrorGuide';
import {gardenJourney,gardenCommandState} from '../src/app/garden2/presentation';

test('Rehearsal can be paused and reset after switching to a passenger, including after reload',()=>{
 const w=new GardenWorld('2-3');go(w,'m:stage:0:0');act(w,'switch');
 act(w,'swap:0');const before=w.snapshot();act(w,'play');assert.ok(w.act('beat',true).ok);
 act(w,'switch');assert.equal(w.actor,'luvie');assert.ok(w.state.playing);
 const restored=new GardenWorld('2-3',w.snapshot());act(restored,'play');assert.equal(restored.state.playing,false);
 act(restored,'resetSong');assert.deepEqual(restored.state.actors,before.actors);assert.deepEqual(restored.state.turns,before.turns);assert.equal(restored.state.beat,0);
 assert.equal(restored.flag('raised'),false);assert.equal(restored.state.trial,undefined);
});

test('Chapter guidance reflects live mechanisms after undo and does not promise a disconnected exit',()=>{
 const w=new GardenWorld('1-3');assert.match(gardenJourney(w).next,/转/);assert.equal(gardenJourney(w).steps[0].done,false);
 go(w,'m:garden:0:0');act(w,'turn:garden');assert.equal(gardenJourney(w).steps[0].done,true);
 w.undo();assert.equal(gardenJourney(w).steps[0].done,false);
 const pond=new GardenWorld('2-1');const before=pond.snapshot();const result=gardenCommandState(pond,'use:care');assert.equal(result.available,false);assert.match(result.reason,/清露/);assert.deepEqual(pond.snapshot(),before);assert.equal(pond.canUndo,false);
});

test('Every chapter guidance survives intermediate saves and finishes only after explicit planting',()=>{
 for(const level of GARDEN_LEVELS){const w=new GardenWorld(level.id);
  for(const step of GARDEN_SOLUTIONS[level.id]){const guide=gardenJourney(new GardenWorld(level.id,w.snapshot()));assert.ok(guide.current>=0,level.id);assert.equal(guide.steps.at(-1)!.done,false);assert.ok(guide.next.length>0);if(step.startsWith('!'))act(w,step.slice(1));else go(w,step);}
  const done=gardenJourney(w);assert.equal(done.done,done.total);assert.equal(done.current,-1);
 }
});

test('2-2 map guidance follows the real mirror states through carrying, rotation, undo and reload',()=>{
 const w=new GardenWorld('2-2');assert.equal(mirrorGuidance(w)!.stage,'take');assert.equal(mirrorGuidance(w)!.tile,'f:4:3');
 go(w,'f:4:3');act(w,'take:mirrorB');const carried=w.snapshot();assert.equal(mirrorGuidance(w)!.stage,'place');assert.equal(mirrorGuidance(w)!.tile,'f:1:0');
 assert.equal(mirrorGuidance(new GardenWorld('2-2',carried))!.stage,'place');
 go(w,'f:1:0');act(w,'drop:mirrorB:f:1:0');assert.equal(mirrorGuidance(w)!.stage,'turn-a');
 assert.equal(mirrorGuidance(w)!.action,'angle:mirrorA');act(w,'angle:mirrorA');assert.equal(mirrorGuidance(w)!.stage,'turn-b');
 act(w,'angle:mirrorB');assert.equal(w.ready(),true);assert.equal(mirrorGuidance(w)!.stage,'plant');
 assert.ok(w.undo());assert.equal(mirrorGuidance(w)!.stage,'turn-b');assert.equal(w.ready(),false);
 act(w,'angle:mirrorB');go(w,'f:4:0');act(w,'repair');assert.equal(mirrorGuidance(w),undefined);
});
test('2-2 guidance can recover a mirror placed on a different floor and does not change the puzzle',()=>{
 const w=new GardenWorld('2-2');go(w,'f:4:3');act(w,'take:mirrorB');act(w,'drop:mirrorB:f:4:3');const before=w.snapshot();
 const guide=mirrorGuidance(w)!;assert.equal(guide.stage,'take');assert.equal(guide.tile,'f:4:3');assert.deepEqual(w.snapshot(),before);assert.match(w.hint().message,/发光/);
});

test('Valley terraces expose real stairs without connecting gaps or impassable height differences',()=>{
 for(const level of GARDEN_LEVELS.filter(l=>l.chapter==='valley')){
  const w=new GardenWorld(level.id);assert.ok(new Set(w.tiles.map(t=>t.h)).size>=2,level.id);
  for(const [low,high]of terrainSteps(w.tiles)){assert.ok(w.neighbors(low.id,'buddy').some(t=>t.id===high.id),`${level.id} ${low.id} -> ${high.id}`);assert.ok(high.h>low.h);}
 }
 assert.equal(terrainSteps([{id:'a',x:0,z:0,h:0},{id:'gap',x:2,z:0,h:1},{id:'high',x:0,z:1,h:2}]).length,0);
 const w=new GardenWorld('1-2');for(const dir of ['up','right','right','down'])act(w,`grow:root:${dir}`);
 assert.ok(terrainSteps(w.tiles).some(([low,high])=>low.x===3&&low.z===1&&low.h===0&&high.id==='f:4:1'));assert.ok(w.pathTo('f:4:1'));
});
test('Cliff faces stop at adjacent floors and pond bounds include the entire moving-garden route',()=>{
 const tile={id:'high',x:0,z:0,h:2};assert.equal(faceDepth(tile,{id:'same',x:1,z:0,h:2},112),0);
 assert.equal(faceDepth(tile,{id:'low',x:1,z:0,h:1},112),TERRAIN_RISE);assert.equal(faceDepth(tile,undefined,112),112+2*TERRAIN_RISE);
 const pond=GARDEN_LEVELS.find(l=>l.id==='2-4')!,bounds=pondFootprint(pond);assert.ok(Math.max(...bounds.map(p=>p.x))>11);
 assert.ok(GARDEN_LEVELS.find(l=>l.id==='2-2')!.tiles.some(t=>t.kind==='water'));
});
test('Garden butterflies vary in size, rest on flowers, and move continuously across landing/takeoff cycles',()=>{
 const first=[0,1,2,3].map(i=>butterflyPose(i,0));assert.equal(new Set(first.map(p=>p.size)).size,4);assert.ok(first.some(p=>p.perched));assert.ok(first.some(p=>!p.perched));assert.ok(new Set(first.map(p=>`${Math.round(p.x)},${Math.round(p.y)}`)).size>=3);
 for(let i=0;i<4;i++){let flying=false,resting=false;for(let t=0;t<100000;t+=30){const a=butterflyPose(i,t),b=butterflyPose(i,t+30);assert.ok(Math.hypot(a.x-b.x,a.y-b.y)<2,'no jump between flowers');flying||=!a.perched;resting||=a.perched;}assert.ok(flying&&resting);}
});
test('Mole greets on approach, waits during distant changes, and avoids repeated boundary greetings',()=>{
 const w=new GardenWorld('1-4'),before=w.snapshot(),conversation=new MoleConversation();
 assert.ok(!w.commands().some(c=>c.id==='talk:mole'));
 assert.equal(conversation.update(w.state,false,0),undefined);
 assert.match(conversation.update(w.state,true,100)!,/门铃/);
 assert.equal(conversation.update(w.state,true,8200),undefined,'greeting ends without looping');
 assert.equal(conversation.update(w.state,false,8300),undefined);
 assert.equal(conversation.update(w.state,true,8400),undefined,'brief boundary crossing does not repeat greeting');
 assert.deepEqual(w.snapshot(),before,'dialogue never modifies puzzle or save state');
 conversation.update(w.state,false,8500);w.state.items.bell.holder='luvie';w.state.items.bell.tile='';
 assert.equal(conversation.update(w.state,false,9000),undefined,'finding bell remotely is quiet');
 assert.match(conversation.update(w.state,true,10000)!,/小门铃/,'returning with bell triggers new line');
 w.state.flags.push('home');assert.match(conversation.update(w.state,true,11000)!,/谢谢/,'returning bell updates nearby dialogue');
 w.state.completed=true;assert.equal(moleDialogue(w.state).stage,'restored');assert.match(conversation.update(w.state,true,12000)!,/花开/);
 conversation.update(w.state,false,21000);assert.match(conversation.update(w.state,true,33000)!,/常来/,'a later visit greets again');
});
export function go(w:GardenWorld,tile:string){const path=w.pathTo(tile);assert.ok(path,`${w.level.id}/${w.actor} ${w.state.actors[w.actor]} -> ${tile}`);for(const id of path){const result=w.move(id);assert.ok(result.ok,`${w.level.id} move ${id}: ${result.message}`);}}
function act(w:GardenWorld,id:string){const result=w.act(id);assert.ok(result.ok,`${w.level.id}/${w.actor}/${id}: ${result.message}`);}
test('Dew changes from plant to parcel once picked; dropping, undo and save restore preserve its form',()=>{
 const w=new GardenWorld('2-1');go(w,'f:0:4');const before=w.snapshot();
 assert.notEqual(w.state.items.dew.picked,true);act(w,'take:dew');assert.equal(w.state.items.dew.picked,true);assert.equal(w.state.items.dew.holder,'luvie');
 act(w,'drop:dew:f:0:4');assert.equal(w.state.items.dew.picked,true);assert.equal(w.state.items.dew.holder,undefined);
 assert.equal(new GardenWorld('2-1',w.snapshot()).state.items.dew.picked,true);
 assert.equal(w.undo(),true);assert.equal(w.state.items.dew.holder,'luvie');assert.equal(w.undo(),true);assert.deepEqual(w.snapshot(),before);
 act(w,'take:dew');go(w,'m:float:0:0');act(w,'use:care');assert.equal(w.state.items.dew.holder,undefined);assert.equal(w.state.items.dew.tile,'');assert.equal(w.state.items.dew.picked,true);
});
test('Existing carried dew saves acquire parcel presentation without losing position or progress',()=>{
 const w=new GardenWorld('2-1');go(w,'f:0:4');act(w,'take:dew');const old=w.snapshot();delete old.items.dew.picked;
 const restored=new GardenWorld('2-1',old);assert.equal(restored.state.items.dew.picked,true);assert.equal(restored.state.items.dew.holder,'luvie');assert.deepEqual(restored.state.actors,old.actors);assert.deepEqual(restored.state.flags,old.flags);
});
test('1-4 flower gate blocks the garden until the bell is returned; core and fountain occupy separate tiles',()=>{
 const w=new GardenWorld('1-4');assert.equal(w.pathTo('f:-9:0'),null);assert.equal(w.pathTo('f:-6:0'),null);
 for(const step of GARDEN_SOLUTIONS['1-4']){if(step==='!repair')break;if(step.startsWith('!'))act(w,step.slice(1));else go(w,step);}
 assert.ok(w.flag('home'));assert.ok(w.pathTo('f:-9:0'));assert.equal(w.pathTo('f:-9:-2'),null);assert.equal(w.level.marks.find(m=>m.id==='core')!.tile,'f:-9:0');
 assert.ok(new GardenWorld('1-4',w.snapshot()).pathTo('f:-9:0'));act(w,'repair');assert.equal(w.state.completed,true);
});
test('1-2 map guidance follows either chosen root route and identifies the fourth socket',()=>{
 for(const directions of [['up','right','right','down'],['down','right','right','up']]){
  const w=new GardenWorld('1-2');go(w,'f:1:1');
  for(const [i,dir]of directions.entries()){const guide=w.growthGuidance()!;assert.equal(guide.retract,false);assert.equal(guide.route.length,4-i);const [dx,dz]=({up:[0,-1],down:[0,1],right:[1,0]} as Record<string,number[]>)[dir];if(i>0)assert.deepEqual(guide.route[0],{x:guide.end.x+dx,z:guide.end.z+dz,h:0});act(w,`grow:root:${dir}`);}
  assert.equal(w.growthGuidance(),undefined);
 }
});
test('Every unfinished garden returns its own readable hint instead of accessing another level’s items',()=>{
 for(const level of GARDEN_LEVELS){const w=new GardenWorld(level.id);assert.doesNotThrow(()=>w.hint(),level.id);assert.ok(w.hint().message.length>0);}
 const w=new GardenWorld('1-2');go(w,'f:1:1');act(w,'grow:root:up');assert.equal(w.ready(),false);assert.ok(w.hint().message.includes('四节芽'));
});
test('1-2 incomplete root at the flowerbed gives a readable planting refusal and can be finished',()=>{
 const w=new GardenWorld('1-2');go(w,'f:1:1');for(const direction of ['up','right','right'])act(w,`grow:root:${direction}`);go(w,'f:4:1');
 const result=w.act('repair');assert.equal(result.ok,false);assert.ok(result.message.includes('四节芽'));assert.equal(result.message.includes('Cannot read'),false);
 go(w,'f:1:1');act(w,'grow:root:down');go(w,'f:4:1');act(w,'repair');assert.equal(w.state.completed,true);
});
test('Holding the lever from every offered neighboring tile opens the actual bridge and survives reload',()=>{
 for(const tile of ['f:-3:0','f:-4:0','f:-2:0','f:-3:-1','f:-3:1']){const w=new GardenWorld('1-4');go(w,tile);act(w,'use:hold');act(w,'switch');assert.ok(w.pathTo('f:3:5'),tile);const restored=new GardenWorld('1-4',w.snapshot());assert.ok(restored.pathTo('f:3:5'),`restored ${tile}`);}
});
function arrangePosts(w:GardenWorld){for(const step of GARDEN_SOLUTIONS['3-2']){if(step==='f:-1:1')break;if(step.startsWith('!'))act(w,step.slice(1));else go(w,step);}}
export function collectReachable(w:GardenWorld){const origin=w.state.actors[w.actor];for(const c of w.level.collectibles)if(!w.state.collected.includes(c.id)&&w.pathTo(c.tile)){go(w,c.tile);go(w,origin);}}
for(const l of GARDEN_LEVELS)test(`2.0 ${l.id}: authored solution survives every save and reaches explicit planting`,()=>{
 let w=new GardenWorld(l.id);
 for(const instruction of GARDEN_SOLUTIONS[l.id]){
  if(instruction.startsWith('!'))act(w,instruction.slice(1));else go(w,instruction);
  const snapshot=w.snapshot();w=new GardenWorld(l.id,JSON.parse(JSON.stringify(snapshot)));assert.deepEqual(w.snapshot(),snapshot,`${l.id} ${instruction} restore`);
 }
 assert.equal(w.state.completed,true);assert.ok(w.together);
});
test('2.0 collection budgets total 56 and each level has two observation points',()=>{assert.equal(GARDEN_LEVELS.reduce((n,l)=>n+l.total,0),56);for(const l of GARDEN_LEVELS){assert.equal(l.marks.filter(m=>m.kind==='rest'||m.kind==='observe').length,2);if(l.id!=='3-4')assert.equal(l.collectibles.length,l.total);}});
for(const l of GARDEN_LEVELS)test(`2.0 ${l.id}: all ${l.total} spores are attainable without fabricating rewards`,()=>{
 const w=new GardenWorld(l.id);collectReachable(w);
 for(const instruction of GARDEN_SOLUTIONS[l.id]){if(instruction==='!repair')collectReachable(w);if(instruction.startsWith('!'))act(w,instruction.slice(1));else go(w,instruction);}
 assert.equal(w.state.collected.length,l.total,l.id);
});
test('2.0 four-bud construction has exactly two complete routes and every dead end retracts',()=>{
 const first=new GardenWorld('1-2');go(first,'f:1:1');const queue=[first.snapshot()],seen=new Set<string>();let solved=0;
 for(let i=0;i<queue.length;i++){const w=new GardenWorld('1-2',queue[i]),key=JSON.stringify(w.state.growth.root);if(seen.has(key))continue;seen.add(key);if(w.connected())solved++;
  for(const c of w.commands().filter(c=>c.id.startsWith('grow:'))){const n=new GardenWorld('1-2',w.snapshot());assert.ok(n.act(c.id).ok);queue.push(n.snapshot());}
  const back=new GardenWorld('1-2',w.snapshot());while(back.state.growth.root.length)assert.ok(back.act('retract:root').ok);assert.equal(back.budget,4);
 }assert.equal(solved,2);assert.ok(seen.size>8);
});
test('2.0 an occupied root cannot disappear, and rejection does not change state',()=>{
 const w=new GardenWorld('1-2');go(w,'f:1:1');act(w,'grow:root:up');go(w,'g:root:1:0');const s=w.snapshot();assert.equal(w.act('retract:root').ok,false);assert.deepEqual(w.snapshot(),s);
});
test('2.0 rotating a module carries an off-centre passenger using the same tile identity',()=>{
 const w=new GardenWorld('1-3');go(w,'m:garden:-1:0');const id=w.state.actors.luvie,old={...w.point};act(w,'turn:garden');assert.equal(w.state.actors.luvie,id);assert.equal(w.point.x,-old.z||0);assert.equal(w.point.z,old.x);assert.notDeepEqual(w.point,old);assert.ok(w.undo());assert.deepEqual(w.point,old);
});
test('2.0 a placed mirror rides a turning courtyard, while carried mirrors have one owner',()=>{
 const w=new GardenWorld('3-4');for(const step of GARDEN_SOLUTIONS['3-4']){if(step==='m:lift:0:0')break;if(step.startsWith('!'))act(w,step.slice(1));else go(w,step);}
 assert.equal(w.state.items.mirror.holder,'luvie');assert.equal(w.state.items.mirror.tile,'');go(w,'m:inner:-1:0');act(w,'drop:mirror:m:inner:-1:0');const before={...w.pointFor(w.state.items.mirror.tile)};act(w,'turn:inner');assert.equal(w.state.items.mirror.tile,before.id);assert.equal(w.state.items.mirror.holder,undefined);assert.notEqual(w.pointFor(before.id).z,before.z);
});
test('2.0 both actors obey low-arch and heavy-lever rules',()=>{
 const w=new GardenWorld('1-4');act(w,'use:hold');assert.equal(w.pathTo('f:3:5','luvie'),null);assert.ok(w.pathTo('f:3:5','buddy'));act(w,'switch');assert.equal(w.act('use:hold').ok,false);go(w,'f:3:5');act(w,'switch');assert.ok(w.pathTo('f:-3:5'));
});
test('2.0 mirrors trace real positions: a correct normal in the wrong place does not work',()=>{
 const w=new GardenWorld('2-2');go(w,'f:1:1');act(w,'angle:mirrorA');go(w,'f:4:3');act(w,'angle:mirrorB');assert.equal(w.beamHits(4,0),false);act(w,'take:mirrorB');go(w,'f:1:0');act(w,'drop:mirrorB:f:1:0');assert.equal(w.beamHits(4,0),true);assert.ok(w.rays().some(p=>p.x===1&&p.z===0));
});
for(const song of [['turn','rise','rest'],['rest','turn','rise'],['rise','turn','rest']])test(`2.0 action song ${song.join('/')} executes causally and resets passengers`,()=>{
 const w=new GardenWorld('2-3');go(w,'m:stage:0:0');act(w,'switch');go(w,'f:-4:0');
 for(let i=0;i<3;i++){let j=w.state.song.indexOf(song[i]);while(j>i){act(w,`swap:${j-1}`);j--;}}
 const initial=w.snapshot();for(let i=0;i<3;i++)act(w,'beat');assert.equal(!!w.pathTo('f:0:-4','luvie'),song.indexOf('turn')<song.indexOf('rise'));act(w,'resetSong');assert.deepEqual(w.snapshot(),initial);
});
for(const firstMode of [0,1])test(`2.0 retaining ${firstMode?'moon':'sun'} gives a real connected route`,()=>{
 const w=new GardenWorld('3-2');arrangePosts(w);if(firstMode){go(w,'f:-1:0');act(w,'valve:mode');}go(w,'f:-1:1');act(w,'freeze');go(w,'f:-1:0');act(w,'valve:mode');go(w,'f:3:4');act(w,'repair');assert.equal(w.state.completed,true);
});
test('2.0 a projection change cannot delete the other actor’s occupied floor',()=>{
 const w=new GardenWorld('3-2');arrangePosts(w);go(w,'f:-1:1');act(w,'freeze');go(w,'f:-1:0');act(w,'valve:mode');go(w,'shadow:moon:2');act(w,'switch');go(w,'f:-1:0');const s=w.snapshot();assert.equal(w.act('valve:mode').ok,false);assert.deepEqual(w.snapshot(),s);
});
test('2.0 all four coupled-water orientations can return to the solvable layout',()=>{
 for(let turns=0;turns<4;turns++){const w=new GardenWorld('3-3');go(w,'m:water:0:0');for(let i=0;i<turns;i++)act(w,'turn:water');while(w.state.turns.water!==0)act(w,'turn:water');for(const step of GARDEN_SOLUTIONS['3-3']){if(step.startsWith('!'))act(w,step.slice(1));else go(w,step);}assert.equal(w.state.completed,true);}
});
test('2.0 final planting checks current light, not just the historical star reward',()=>{
 const w=new GardenWorld('3-4');for(const step of GARDEN_SOLUTIONS['3-4']){if(step==='!repair')break;if(step.startsWith('!'))act(w,step.slice(1));else go(w,step);}assert.equal(w.ready(),true);
 go(w,'f:1:-4');go(w,'m:lift:0:0');act(w,'valve:lift');go(w,'m:light:0:0');act(w,'turn:light');assert.equal(w.flag('star'),true);assert.equal(w.beamHits(-4,0),false);assert.equal(w.ready(),false);
});
test('2.0 bad saves fall back safely; replay progress and completed memories remain independent',()=>{
 const w=new GardenWorld('1-2');assert.deepEqual(new GardenWorld('1-2',{...w.snapshot(),actors:{luvie:'void',buddy:'void'}}).snapshot(),w.snapshot());
 for(const step of GARDEN_SOLUTIONS['1-2']){if(step.startsWith('!'))act(w,step.slice(1));else go(w,step);}
 const old={playerName:'露薇',levels:{'1-1':{completed:true,bestStars:3}}},before=JSON.stringify(old);
 const p=normalizeGardenProgress({version:1,lastLevel:'1-2',legacy:old,runs:{'1-2':new GardenWorld('1-2').snapshot()},memories:{'1-2':w.snapshot()},records:{'1-2':{completed:true,stars:3,collected:3}}});assert.equal(p.runs['1-2'].completed,false);assert.equal(p.memories['1-2'].completed,true);assert.equal(JSON.stringify(old),before);assert.deepEqual(p.legacy,old);
});
test('2.0 retained shadows store geometry rather than tracking a subsequently moved pillar',()=>{
 const w=new GardenWorld('3-2');arrangePosts(w);go(w,'f:-1:1');act(w,'freeze');go(w,'f:-1:0');act(w,'valve:mode');go(w,'f:0:0');const before=JSON.stringify(w.state.shadowMemory);act(w,'take:sunPost');assert.equal(w.projection(0).length,0);assert.ok(w.tiles.some(t=>t.id==='shadow:sun'));assert.equal(JSON.stringify(w.state.shadowMemory),before);assert.ok(w.pathTo('f:3:4'));assert.deepEqual(new GardenWorld('3-2',w.snapshot()).state.shadowMemory,w.state.shadowMemory);
});
test('2.0 1-2 following buddy can catch up one real tile at a time before final planting',()=>{
 const original=new GardenWorld('1-2');for(const step of GARDEN_SOLUTIONS['1-2']){if(step==='!repair')break;if(step.startsWith('!'))act(original,step.slice(1));else go(original,step);}
 const saved=original.snapshot();saved.actors.buddy='f:0:1';saved.follow=true;const w=new GardenWorld('1-2',saved);
 for(let steps=0;!w.together&&steps<15;steps++){const before=w.pointFor(w.state.actors.buddy);assert.ok(w.commands().some(c=>c.id==='rejoin'));act(w,'rejoin');const after=w.pointFor(w.state.actors.buddy);assert.equal(Math.abs(before.x-after.x)+Math.abs(before.z-after.z),1);}
 assert.ok(w.together);act(w,'repair');assert.equal(w.state.completed,true);
});

test('2.0 completed gardens allow walking and observing but do not reopen structural controls',()=>{
 const w=new GardenWorld('1-2');for(const step of GARDEN_SOLUTIONS['1-2']){if(step.startsWith('!'))act(w,step.slice(1));else go(w,step);}const count=w.state.collected.length;go(w,'f:5:1');assert.equal(w.state.completed,true);assert.equal(w.act('grow:root:right').ok,false);assert.equal(w.state.collected.length,count);assert.equal(w.commands().some(c=>c.id==='repair'),false);
});
