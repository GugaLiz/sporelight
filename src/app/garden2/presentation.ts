import {GardenWorld} from './world';

export interface GardenMilestone {label:string;done:boolean}
export function gardenJourney(w:GardenWorld) {
 const s=w.state,flag=(id:string)=>w.flag(id),steps:GardenMilestone[]=[];
 const add=(label:string,done:boolean)=>steps.push({label,done:s.completed||done});
 switch(w.level.id){
  case '1-1':case '1-2':add('接通根路',w.connected());break;
  case '1-3':add('转庭接北岸',!!w.pathTo('f:0:-4','luvie'));break;
  case '1-4':add('固定归途',flag('latch'));add('归还门铃',flag('home'));break;
  case '2-1':add('清露养睡莲',flag('care'));add('中水位靠岸',s.water===1);break;
  case '2-2':add('镜叶入槽',s.items.mirrorB.tile==='f:1:0');add('光照花床',w.beamHits(4,0));break;
  case '2-3':add('转庭后升台',flag('raised')&&s.turns.stage===1);add('固定便道',flag('latch'));break;
  case '2-4':add('种下蜜花',flag('plant'));add('载光虫授粉',flag('pollinated'));break;
  case '3-1':add('照亮石窗',flag('window'));add('随身带暖灯',!!s.items.lamp.holder);break;
  case '3-2':add('安放日月柱',s.items.sunPost.tile==='f:0:0'&&s.items.moonPost.tile==='f:3:-1');add('两段影路相接',w.ready()&&!!w.pathTo('f:3:4','luvie'));break;
  case '3-3':add('藤根学会蓄水',flag('root'));add('分水托起花台',s.turns.water===1&&s.turns.lift===1);break;
  case '3-4':add('固定叶阶',flag('root'));add('水托花台',flag('rain')&&s.turns.water===1);add('光回到家',flag('star')&&w.beamHits(-4,0));add('接通归途',s.turns.inner===1);break;
 }
 const core=w.level.marks.find(m=>m.kind==='core')!;
 add(w.level.dual?'两位到花床':'抵达花床',steps.every(step=>step.done)&&w.near(core.tile,'luvie')&&w.together);
 add('种下微光',s.completed);
 const current=steps.findIndex(step=>!step.done);
 return {steps,current,done:steps.filter(step=>step.done).length,total:steps.length,
  next:s.completed?w.level.story:w.ready()&&steps.slice(0,-2).every(step=>step.done)?(w.near(core.tile,'luvie')?(w.together?'花床已准备好，点击「一起种下微光」完成修复。':'伙伴还没到身边。开启同行等它跟上，或换手带它回来。'):'道路已准备好，带着伙伴前往核心花床。'):w.hint().message};
}

/** Probe a copy so disabled controls explain the actual rules without changing history. */
export function gardenCommandState(w:GardenWorld,id:string){
 const probe=new GardenWorld(w.level.id,w.snapshot());
 const result=probe.act(id);
 return {available:result.ok,reason:result.ok?'':result.message};
}
