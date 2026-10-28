import test from 'node:test';
import assert from 'node:assert/strict';
import { CLOUD_LEVELS, tileId } from '../src/app/cloud/data';
import { CloudModel, normalizeCloudSave, emptyCloudSave, CLOUD_SAVE_KEY } from '../src/app/cloud/model';
import { createDefaultSave, normalizeSave } from '../src/app/save';

export const CLOUD_SOLUTIONS:Record<string,string[]>={
  'cloud-1':['@wind','!discover:wind','@letter','!discover:letter','@seed','!seed','@turn','!rotate','@finish','!repair'],
  'cloud-2':['@rain','!discover:rain','lift:6:4','!lift','@bird','!discover:bird','@finish','!repair'],
  'cloud-3':['@home','!discover:home','@pad','!wait','@latch','!latch','@star','!discover:star','@pad','!call','@turn','!rotate','@finish','!repair'],
};
const walk=(m:CloudModel,target:string)=>{const path=m.pathTo(target);assert.ok(path,`${m.id}: ${m.state.tile} -> ${target}`);for(const id of path)assert.ok(m.move(id));};
const landmark=(m:CloudModel,id:string)=>{const l=m.level.landmarks.find(l=>l.id===id)!;const p=m.landmarkPoint(l);return m.tiles.find(t=>t.x===p.x&&t.z===p.z&&t.h===p.h)!.id;};

for(const level of CLOUD_LEVELS)test(`${level.id}: full exploration solution and per-step save restoration`,()=>{
  let model=new CloudModel(level.id);
  for(const instruction of CLOUD_SOLUTIONS[level.id]){
    if(instruction.startsWith('!'))assert.ok(model.act(instruction.slice(1)).ok,instruction);
    else {const target=instruction.startsWith('@')?landmark(model,instruction.slice(1)):instruction;const path=model.pathTo(target);assert.ok(path,instruction);for(const tile of path){assert.ok(model.move(tile));const saved=model.snapshot();model=new CloudModel(level.id,JSON.parse(JSON.stringify(saved)));assert.deepEqual(model.snapshot(),saved);}}
    const state=model.snapshot();model=new CloudModel(level.id,state);assert.deepEqual(model.snapshot(),state);
  }
  assert.equal(model.state.repaired,true);assert.equal(model.state.found.length,2);assert.equal(model.state.buddy,'sit');
});

test('Rotation updates physical connections and cannot be operated remotely or from its bridge',()=>{
  const m=new CloudModel('cloud-1');assert.equal(m.pathTo(tileId(10,3)),null);assert.equal(m.act('rotate').ok,false);
  walk(m,tileId(4,3));assert.ok(m.act('rotate').ok);assert.ok(m.pathTo(tileId(10,3)));assert.equal(m.pathTo(tileId(4,-3)),null);
  walk(m,'bridge:6:3');assert.equal(m.act('rotate').ok,false);
  assert.ok(m.undo());assert.equal(m.state.tile,tileId(5,3));assert.ok(m.undo());assert.equal(m.state.tile,tileId(4,3));assert.ok(m.undo());assert.equal(m.state.bridge,'north');
});

test('Lift carries a stable tile ID, restores mid-journey, and can always be lowered on board',()=>{
  const m=new CloudModel('cloud-2');walk(m,'lift:7:3');const original=m.snapshot();assert.ok(m.act('lift').ok);
  assert.equal(m.current.h,3);assert.equal(m.state.tile,'lift:7:3');assert.ok(m.pathTo(tileId(10,4)));assert.equal(m.pathTo(tileId(1,7)),null);
  const restored=new CloudModel('cloud-2',m.snapshot());assert.equal(restored.current.h,3);assert.ok(restored.act('lift').ok);assert.equal(restored.current.h,0);assert.ok(restored.pathTo(tileId(1,7)));
  assert.ok(m.undo());assert.deepEqual(m.snapshot(),original);
  walk(m,'lift:6:4');m.act('lift');
  const away=new CloudModel('cloud-2',{...m.snapshot(),tile:tileId(5,4)});assert.equal(away.current.h,0);assert.equal(away.pathTo('lift:6:4'),null);assert.ok(away.act('lift').ok);assert.ok(away.pathTo('lift:6:4'));
});

test('Companion must wait, permanent latch keeps gate open, and reunion requires returning in person',()=>{
  const m=new CloudModel('cloud-3');assert.equal(m.pathTo(tileId(8,6)),null);walk(m,tileId(3,6));assert.ok(m.act('wait').ok);
  assert.ok(m.pathTo(tileId(8,6)));assert.equal(m.act('call').ok,false);walk(m,tileId(8,6));assert.equal(m.act('call').ok,false);
  assert.ok(m.act('latch').ok);assert.equal(m.act('call').ok,false);walk(m,tileId(3,6));assert.ok(m.act('call').ok);assert.equal(m.state.buddy,'follow');assert.ok(m.pathTo(tileId(8,6)));
  assert.ok(m.undo());assert.equal(m.state.buddy,'wait');assert.equal(m.state.latch,true);
});

test('Optional discoveries never gate completion and missing seed does',()=>{
  const m=new CloudModel('cloud-1');walk(m,tileId(4,3));m.act('rotate');walk(m,tileId(10,3));assert.equal(m.act('repair').ok,false);
  walk(m,tileId(4,3));m.act('rotate');walk(m,tileId(4,-3));m.act('seed');walk(m,tileId(4,3));m.act('rotate');walk(m,tileId(10,3));assert.ok(m.act('repair').ok);assert.deepEqual(m.state.found,[]);
});

for(const level of CLOUD_LEVELS)test(`${level.id}: every reachable puzzle state has a route to completion`,()=>{
  // Search actual legal transitions, then reverse the graph from all completed states.
  const first=new CloudModel(level.id).snapshot();const states=[first],key=(s:typeof first)=>JSON.stringify({...s,found:[]});
  const seen=new Map([[key(first),0]]),reverse:number[][]=[[]],done:number[]=[];
  for(let i=0;i<states.length;i++){
    const m=new CloudModel(level.id,states[i]);if(m.state.repaired){done.push(i);continue;}
    const transitions=[...m.neighbors(m.state.tile).map(t=>({move:t.id})),...m.actions().filter(a=>a.id!=='pet'&&!a.id.startsWith('discover:')).map(a=>({action:a.id}))];
    for(const transition of transitions){const next=new CloudModel(level.id,m.snapshot());const ok='move'in transition?next.move(transition.move):next.act(transition.action).ok;if(!ok)continue;const state=next.snapshot(),k=key(state);let index=seen.get(k);if(index===undefined){index=states.length;seen.set(k,index);states.push(state);reverse.push([]);}reverse[index].push(i);}
    assert.ok(states.length<10000,'bounded puzzle state graph');
  }
  assert.ok(done.length>0);const reachable=new Set(done);for(let i=0;i<done.length;i++)for(const prev of reverse[done[i]])if(!reachable.has(prev)){reachable.add(prev);done.push(prev);}
  assert.equal(reachable.size,states.length,`${states.length-reachable.size} stranded states`);
});

test('Malformed sample saves normalize safely and never modify legacy progress',()=>{
  const legacy=createDefaultSave();legacy.playerName='露薇';legacy.levels['1-1'].completed=true;const before=JSON.stringify(legacy),normalizedBefore=normalizeSave(legacy);
  const sample=normalizeCloudSave({version:1,lastLevel:'bogus',completed:['cloud-1','bogus'],runs:{'cloud-1':{version:1,levelId:'cloud-1',tile:'void',bridge:'x',found:['letter','void'],buddy:'bogus'}},discoveries:{'cloud-1':['wind','void']}});
  assert.deepEqual(sample.completed,['cloud-1']);assert.equal(new CloudModel('cloud-1',sample.runs['cloud-1']).current.id,tileId(1,7));assert.deepEqual(sample.runs['cloud-1']!.found,['letter']);
  assert.deepEqual(sample.discoveries['cloud-1'],['wind']);assert.equal(JSON.stringify(legacy),before);assert.deepEqual(normalizeSave(legacy),normalizedBefore);assert.notEqual(CLOUD_SAVE_KEY,'sporelight.save.v2');
  assert.deepEqual(normalizeCloudSave(null),emptyCloudSave());assert.deepEqual(normalizeCloudSave({version:99}),emptyCloudSave());
});
