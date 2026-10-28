import test from 'node:test';
import assert from 'node:assert/strict';
import { characterPose, facingFor, jumpHeight, WALK_FRAME_MS, WALK_CYCLE_MS, type MotionInput } from '../src/app/game/characterMotion';
const input: MotionInput = {time:0,facing:'front',lowMotion:false,complete:false};

test('Walking uses twelve intermediate frames and faces the destination',()=>{
  const travel={startedAt:100,progress:.5,jump:false,rolling:false,distance:240};
  const keys=Array.from({length:12},(_,i)=>characterPose({...input,time:100+i*WALK_FRAME_MS,facing:'left',travel}).key);
  assert.equal(new Set(keys).size,12);
  assert.equal(characterPose({...input,time:100+WALK_CYCLE_MS,travel}).key,keys[0]);
  assert.equal(characterPose({...input,time:220,facing:'right',travel}).flip,true);
  assert.equal(characterPose({...input,time:220,facing:'left',travel}).flip,false);
  assert.equal(facingFor(120,-20),'right');assert.equal(facingFor(-120,20),'left');
  assert.equal(facingFor(10,-100),'back');assert.equal(facingFor(-10,100),'front');
});
test('Sowing plays once from its own start and holds the final supplied pose',()=>{
  const action={kind:'sow' as const,startedAt:5000};
  const keys=[0,140,280,420,560].map(dt=>characterPose({...input,time:5000+dt,action}).key);
  assert.deepEqual(keys,['sow-1','sow-2','sow-3','sow-4','sow-5']);
  assert.equal(characterPose({...input,time:5899,action}).key,'sow-5');
  assert.equal(characterPose({...input,time:5900,action}).clip,'idle');
  assert.equal(characterPose({...input,time:5900,action:{...action,startedAt:5900}}).key,'sow-1');
});
test('Rear movement animates a full limb cycle instead of holding the idle back',()=>{
  const travel={startedAt:0,progress:.5,jump:false,rolling:false,distance:240};
  const poses=Array.from({length:12},(_,i)=>characterPose({...input,time:i*WALK_FRAME_MS,facing:'back',travel}));
  assert.equal(new Set(poses.map(p=>p.key)).size,12);
  assert.ok(poses.every(p=>p.clip==='walk-back'&&p.key.startsWith('walk-back-')&&!p.flip));
  assert.equal(characterPose({...input,time:WALK_CYCLE_MS,facing:'back',travel}).key,poses[0].key);
  assert.equal(characterPose({...input,time:WALK_CYCLE_MS,facing:'back'}).key,'idle-back');
});
test('Jump returns to ground, lands with a brief squash, and releases to normal scale',()=>{
  assert.equal(jumpHeight(0,false),0);assert.ok(Math.abs(jumpHeight(1,false))<.001);assert.equal(jumpHeight(.5,false),85);
  const travel={startedAt:0,progress:.05,jump:true,rolling:false,distance:240};
  assert.equal(characterPose({...input,travel}).clip,'takeoff');
  assert.equal(characterPose({...input,travel:{...travel,progress:.5}}).clip,'jump');
  const land=characterPose({...input,travel:{...travel,progress:.9}});
  assert.equal(land.clip,'landing');assert.ok(land.scaleY<1&&land.scaleX>1);
  const finish=characterPose({...input,travel:{...travel,progress:1}});assert.ok(Math.abs(finish.scaleY-1)<.001);
  const keys=Array.from({length:120},(_,i)=>characterPose({...input,travel:{...travel,progress:i/119}}).key);
  assert.equal(new Set(keys).size,12);
  assert.equal(keys[0],'jump-1');assert.equal(keys.at(-1),'jump-12');
  assert.equal(jumpHeight(.1,false),0);assert.ok(Math.abs(jumpHeight(.9,false))<.001);
});
test('Roll mode rotates the ball; completion takes precedence over all action clips',()=>{
  const travel={startedAt:0,progress:.5,jump:false,rolling:true,distance:240};
  const roll=characterPose({...input,time:400,facing:'right',travel});assert.equal(roll.key,'ball');assert.notEqual(roll.rotation,0);
  assert.equal(characterPose({...input,complete:true,travel}).key,'salute');
  assert.equal(characterPose({...input,time:400,action:{kind:'symbiosis',startedAt:0}}).key,'symbiosis');
});
test('Reduced motion supplies a stable standing pose and no jump displacement',()=>{
  const travel={startedAt:0,progress:.5,jump:true,rolling:true,distance:240};
  const a=characterPose({...input,time:100,lowMotion:true,travel});
  const b=characterPose({...input,time:800,lowMotion:true,travel,action:{kind:'sow',startedAt:0}});
  assert.deepEqual(a,b);assert.equal(a.clip,'idle');assert.equal(a.scaleX,1);assert.equal(jumpHeight(.5,true),0);
});
