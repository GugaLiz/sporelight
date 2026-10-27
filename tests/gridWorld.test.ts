import test from 'node:test';
import assert from 'node:assert/strict';
import { LEVELS,getLevel } from '../src/app/game/levels';
import { GridWorld } from '../src/app/game/GridWorld';
import { SOLUTIONS } from './solutions';
import { sameTile } from '../src/app/game/gridLayout';

for(const level of LEVELS)test(`${level.id}: original puzzle solution remains playable over physical floor tiles`,()=>{
 const world=new GridWorld(level);let steps=0;
 for(const instruction of SOLUTIONS[level.id]){
  if(instruction.startsWith('!'))assert.ok(world.act(instruction.slice(1),0,true).ok,`${level.id}: ${instruction}`);
  else {
   const route=world.pathToNode(instruction);assert.ok(route,`${level.id} path ${world.model.state.node} -> ${instruction}`);
   for(const step of route){assert.ok(world.commit(step.position,step.jump).ok,`${level.id} tile ${JSON.stringify(step)}`);steps++;if(world.model.state.completed)break;}
  }
 }
 assert.equal(world.model.state.completed,true,level.id);assert.equal(world.model.stars,3,level.id);
 assert.ok(steps>0||level.id==='2-1');
});
test('A direction moves only one tile, and solid walls are impassable even with jumping',()=>{
 const world=new GridWorld(getLevel('1-1'));const start={...world.position};
 const right=world.destination('right');assert.ok(right);assert.equal(right.x,start.x+1);assert.equal(right.z,start.z);
 assert.ok(world.commit(right).ok);assert.equal(world.model.state.node,'start');
 const wall=[...world.layout.tiles.values()].find(t=>t.solid)!;
 assert.equal(world.tileOpen(wall),false);assert.equal(world.canJump(wall),false);
 assert.equal(world.commit({x:-10,z:-10}).ok,false);
});
test('A one-cell void requires jumping and cannot be walked across',()=>{
 const world=new GridWorld(getLevel('1-1'));
 for(const target of ['fork','stone'])for(const step of world.pathToNode(target)!)world.commit(step.position,step.jump);
 const route=world.pathToNode('end')!;const jump=route.find(s=>s.jump);assert.ok(jump);
 for(const step of route){if(step.jump){assert.equal(world.canStep(step.position),false);assert.equal(world.canJump(step.position),true);break;}world.commit(step.position);}
});
test('Jumping cannot bypass a locked seed bridge or a closed companion gate',()=>{
 for(const [id,target]of [['1-2','pollen'],['1-4','end']]){const world=new GridWorld(getLevel(id));assert.equal(world.pathToNode(target),null);}
});
test('Intermediate position survives a save and undo without losing puzzle state',()=>{
 const world=new GridWorld(getLevel('1-2'));const next=world.destination('right')!;assert.ok(world.commit(next).ok);
 const saved=world.model.snapshot();const restored=new GridWorld(world.model.level,JSON.parse(JSON.stringify(saved)));assert.ok(sameTile(restored.position,next));
 assert.ok(world.undo());assert.ok(sameTile(world.position,world.layout.nodes.start));
});
test('A malformed saved position cannot strand the player beyond a locked route',()=>{
 const base=new GridWorld(getLevel('1-2'));const snapshot=base.model.snapshot();snapshot.gridPosition={x:12,z:7};
 const restored=new GridWorld(base.model.level,snapshot);assert.ok(sameTile(restored.position,restored.layout.nodes.start));
});
test('Walking away from a plant removes its interaction options',()=>{
 const world=new GridWorld(getLevel('1-2'));for(const step of world.pathToNode('north')!)world.commit(step.position,step.jump);
 assert.ok(world.act('plant',0,true).ok);
 const path=world.pathToNode('pollen')!;
 world.commit(path[0].position,path[0].jump);world.commit(path[1].position,path[1].jump);
 assert.deepEqual(world.actions(),[]);assert.equal(world.act('reclaim',0,true).ok,false);
});
