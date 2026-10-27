import test from 'node:test';
import assert from 'node:assert/strict';
import { LEVELS, getLevel, totalSpores } from '../src/app/game/levels';
import { GameModel, type RunState } from '../src/app/game/model';
import { createDefaultSave, normalizeSave, persistSave, loadSave } from '../src/app/save';
import { SOLUTIONS } from './solutions';
const walk = (m: GameModel, id: string) => {const p=m.pathTo(id);assert.ok(p,`Path to ${id}`);for(const step of p.slice(1))assert.ok(m.move(step).ok);};
const action = (m: GameModel,id:string) => assert.ok(m.act(id,0,true).ok,`${m.level.id}/${m.state.node}/${id}`);
for(const level of LEVELS) test(`${level.id}: designed solution, all spores, save round-trip, completion`,()=>{
  let m=new GameModel(level);
  for(const step of SOLUTIONS[level.id]) {
    if(step.startsWith('!'))action(m,step.slice(1));else assert.ok(m.move(step).ok,`${level.id}: ${m.state.node} -> ${step}`);
    if(!m.state.completed) { const snapshot=m.snapshot();m=new GameModel(level,JSON.parse(JSON.stringify(snapshot)));assert.deepEqual(m.snapshot(),snapshot); }
  }
  assert.equal(m.state.completed,true);assert.equal(m.state.collected.length,totalSpores(level));assert.equal(m.stars,3);
  assert.equal(m.act('plant').ok,false);
});
test('One seed must be reclaimed; no second plant, no exit without pollen',()=>{
 const m=new GameModel(getLevel('1-2'));walk(m,'east');action(m,'plant');assert.equal(m.pathTo('end'),null);walk(m,'north');assert.equal(m.act('plant').ok,false);
 walk(m,'east');action(m,'reclaim');walk(m,'north');action(m,'plant');walk(m,'pollen');walk(m,'north');action(m,'reclaim');walk(m,'east');action(m,'plant');assert.ok(m.pathTo('end'));
});
test('Bridge direction and shadow phase are reversible, not permanent unlocks',()=>{
 for(const id of ['1-3','3-2']){const m=new GameModel(getLevel(id));const control=id==='1-3'?'pivot':'dial';const targets=id==='1-3'?['dew','leaf']:['sun','moon'];walk(m,control);action(m,`choose:${targets[0]}`);assert.ok(m.pathTo(targets[0]));assert.equal(m.pathTo(targets[1]),null);action(m,`choose:${targets[1]}`);assert.equal(m.pathTo(targets[0]),null);assert.ok(m.pathTo(targets[1]));}
});
test('Lily jumps require explicit destination and cannot walk over water',()=>{
 const m=new GameModel(getLevel('2-1'));assert.equal(m.pathTo('west'),null);assert.equal(m.interact().ok,false);assert.equal(m.act('jump:end').ok,false);
 action(m,'jump:west');assert.equal(m.state.node,'west');m.undo();assert.equal(m.state.node,'start');assert.equal(m.state.collected.length,0);
});
test('Beam needs the complete chain, breaks again, and handles mirror cycles',()=>{
 const m=new GameModel(getLevel('2-2'));walk(m,'mirrorB');action(m,'choose:crystal');assert.equal(m.beamConnected,false);walk(m,'mirrorA');action(m,'choose:mirrorB');assert.equal(m.beamConnected,true);action(m,'choose:pool');assert.equal(m.beamConnected,false);action(m,'choose:mirrorB');walk(m,'mirrorB');action(m,'choose:mirrorA');assert.equal(m.beamConnected,false);assert.deepEqual(m.beamPath(),['mirrorA','mirrorB']);
});
test('Rain requires both tune order and live timing, reduced motion only relaxes timing',()=>{
 const m=new GameModel(getLevel('2-3'));walk(m,'drum');assert.equal(m.act('note:滴',1800).ok,false);action(m,'note:滴');assert.equal(m.state.tune,1);action(m,'note:叮');assert.equal(m.state.tune,0);assert.equal(m.state.activated.includes('drum'),false);m.undo();assert.equal(m.state.tune,1);assert.equal(m.act('note:咚',1800,true).ok,true);assert.equal(m.state.tune,2);
});
test('Companion can only move one station and undo restores its position',()=>{
 const m=new GameModel(getLevel('2-4'));walk(m,'home');assert.equal(m.act('lure').ok,false);assert.equal(m.state.buddy,'nest');walk(m,'reed');action(m,'lure');assert.equal(m.state.buddy,'reed');m.undo();assert.equal(m.state.buddy,'nest');
});
test('Fog hides paths and prevents targeting hidden nodes before lighting',()=>{
 const m=new GameModel(getLevel('3-1'));assert.equal(m.isVisible('lampB'),false);assert.equal(m.pathTo('lampB'),null);walk(m,'lampA');action(m,'light');assert.equal(m.isVisible('lampB'),true);assert.ok(m.pathTo('lampB'));m.undo();assert.equal(m.isVisible('lampB'),false);
});
test('Water must feed the correct plant; jumping does not bypass dew requirement',()=>{
 const m=new GameModel(getLevel('3-3'));walk(m,'vine');assert.equal(m.act('plant').ok,false);walk(m,'pump');action(m,'choose:lily');walk(m,'lily');assert.equal(m.act('jump:end').ok,false);action(m,'jump:rest');action(m,'jump:lily');walk(m,'pump');action(m,'choose:vine');walk(m,'lily');assert.equal(m.act('jump:rest').ok,false);
});
test('Finale requires collection and symbol memory; wrong order preserves all progress',()=>{
 const m=new GameModel(getLevel('3-4'));walk(m,'leaf');assert.equal(m.act('light').ok,false);
 for(const n of m.level.nodes.filter(n=>n.spore))walk(m,n.id);
 walk(m,'moon');const before=m.snapshot();assert.equal(m.act('light').ok,false);assert.deepEqual(m.snapshot(),before);assert.equal(m.pathTo('end'),null);
 for(const id of ['leaf','rain','star','moon']){walk(m,id);action(m,'light');}walk(m,'end');assert.equal(m.state.completed,true);
});
test('The old walk-and-E strategy cannot solve decision levels',()=>{
 for(const id of ['1-3','2-1','2-2','2-3','3-2','3-3']){const m=new GameModel(getLevel(id));for(let i=0;i<10;i++){for(const n of m.level.nodes){if(m.pathTo(n.id))walk(m,n.id);m.interact(0,true);}}assert.equal(m.state.completed,false,id);}
});
test('Legacy in-progress layouts reset safely while earned progression survives',()=>{
 const save=normalizeSave({hasNamed:true,levels:{valley:{completed:true,bestStars:3}},run:{levelId:'1-1',node:'n0',activated:['n1'],collected:['n0']}});
 assert.equal(save.levels['1-1'].completed,true);assert.equal(save.levels['1-2'].unlocked,true);assert.equal(save.run?.node,'start');assert.deepEqual(save.run?.collected,[]);
});
test('Malformed saves, unavailable storage, and invalid choices fail safely',()=>{
 for(const raw of [null,[],{levels:null,settings:[]},{lastLevel:'3-4',settings:{bgm:5,sfx:-1}}]){const s=normalizeSave(raw);assert.equal(s.lastLevel,'1-1');assert.equal(s.levels['3-4'].unlocked,false);}
 const m=new GameModel(getLevel('1-1'));assert.equal(m.act('jump:end').ok,false);
 Object.defineProperty(globalThis,'localStorage',{configurable:true,value:{setItem(){throw Error('Quota');},getItem(){return '{bad';}}});assert.equal(persistSave(createDefaultSave()),false);assert.equal(loadSave().lastLevel,'1-1');
});
// Exhaustively check that every reachable puzzle state has an escape to completion.
// Canonicalize sets so visiting collectibles in different orders does not explode the graph.
const key=(s:RunState)=>JSON.stringify([s.node,[...s.collected].sort(),[...s.activated].sort(),Object.entries(s.vars).sort(),s.buddy,s.tune,s.completed]);
for(const level of LEVELS) test(`${level.id}: no reachable soft-locks`,()=>{
 const start=new GameModel(level).snapshot();const states=[start];const ids=new Map([[key(start),0]]);const reverse:number[][]=[[]];const terminals:number[]=[];
 for(let i=0;i<states.length;i++){
  const state=states[i];if(state.completed){terminals.push(i);continue;}
  const base=new GameModel(level,state);
  const actions=[...level.nodes.filter(n=>base.edgeOpen(state.node,n.id)).map(n=>({move:n.id,action:''})),...base.actions().map(a=>({move:'',action:a.id}))];
  for(const a of actions){const m=new GameModel(level,state);const r=a.move?m.move(a.move):m.act(a.action,0,true);if(!r.ok)continue;const s=m.snapshot();const k=key(s);let target=ids.get(k);if(target===undefined){target=states.length;ids.set(k,target);states.push(s);reverse.push([]);}reverse[target].push(i);}
  assert.ok(states.length<60000,`${level.id} state space unexpectedly large`);
 }
 const solved=new Set(terminals);const queue=[...terminals];for(let i=0;i<queue.length;i++)for(const id of reverse[queue[i]])if(!solved.has(id)){solved.add(id);queue.push(id);}
 assert.equal(solved.size,states.length,`${level.id}: ${states.length-solved.size} stranded states of ${states.length}`);
});
