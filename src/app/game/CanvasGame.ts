import { CHARACTER_FILES,WALK_TILE_MS,characterPose,facingFor,type Facing,type CharacterAction } from './characterMotion';
import type { SoundKind } from './audio';
import { getLevel,totalSpores } from './levels';
import { type GameModel,type RunState } from './model';
import { GridWorld,type GridStep } from './GridWorld';
import { GridRenderer } from './GridRenderer';
import { GRID_DIRECTIONS,gridKey,sameTile,projectTile,type GridPosition,type GridPoint,type GridDirection } from './gridLayout';
import type { GameSnapshot,SaveData } from '../types';

interface Travel {from:GridPoint;to:GridPoint;progress:number;jump:boolean;landed?:boolean;startedAt:number;duration:number}
export class CanvasGame {
 readonly model:GameModel;
 readonly world:GridWorld;
 private renderer:GridRenderer;
 private raf=0;private last=0;private clock=0;private paused=false;private disposed=false;private reported=false;
 private route:GridStep[]=[];private travel:Travel|null=null;private hintNode?:string;private target:GridPosition|null=null;
 private facing:Facing='front';private rolling=false;private characterAction:CharacterAction|null=null;private clueUntil=0;
 private held:GridDirection|null=null;private lastDirection:GridDirection='up';private blockedUntil=0;private motionStartedAt=0;private lastWalkEnd=-1000;
 private handlers:(()=>void)[]=[];private observer:ResizeObserver;private tip:HTMLElement|null;
 private directionPad:HTMLElement|null;
 private previousView='';private settings:SaveData['settings'];
 constructor(private canvas:HTMLCanvasElement,levelId:string,saved:RunState|null,settings:SaveData['settings'],private onChange:(run:RunState)=>void,private complete:(snapshot:GameSnapshot)=>void,private sound:(kind:SoundKind)=>void){
  this.settings=settings;this.world=new GridWorld(getLevel(levelId),saved);this.model=this.world.model;this.renderer=new GridRenderer(canvas,this.world,settings);this.tip=document.getElementById('gameTip');
  this.directionPad=document.querySelector<HTMLElement>('.grid-direction-pad');
  if(this.directionPad){this.directionPad.classList.add('native-direction-pad');document.querySelector('.shell')?.appendChild(this.directionPad);}
  this.buildTileControls();
  const controls=document.getElementById('gridControls');
  const tileClick=(event:Event)=>{const button=(event.target as HTMLElement).closest<HTMLButtonElement>('[data-grid-tile]');if(!button)return;const [x,z]=button.dataset.gridTile!.split(',').map(Number);this.walkToTile({x,z});};
  controls?.addEventListener('click',tileClick);this.handlers.push(()=>controls?.removeEventListener('click',tileClick));
  const panel=document.getElementById('puzzlePanel');const choose=(event:Event)=>{const button=(event.target as HTMLElement).closest<HTMLButtonElement>('[data-puzzle-action]');if(button)this.perform(button.dataset.puzzleAction!);};panel?.addEventListener('click',choose);this.handlers.push(()=>panel?.removeEventListener('click',choose));
  document.querySelectorAll<HTMLButtonElement>('[data-grid-direction]').forEach(button=>{
   const down=(event:PointerEvent)=>{event.preventDefault();this.held=button.dataset.gridDirection as GridDirection;this.route=[];this.step(this.held);};
   const keyboard=(event:MouseEvent)=>{if(event.detail===0)this.step(button.dataset.gridDirection as GridDirection);};
   button.addEventListener('pointerdown',down);button.addEventListener('click',keyboard);this.handlers.push(()=>{button.removeEventListener('pointerdown',down);button.removeEventListener('click',keyboard);});
  });
  window.addEventListener('pointerup',this.release);window.addEventListener('pointercancel',this.release);window.addEventListener('keydown',this.onKeyDown);window.addEventListener('keyup',this.onKeyUp);window.addEventListener('blur',this.release);
  this.observer=new ResizeObserver(()=>{if(!this.disposed){this.renderer.configure(this.settings);this.previousView='';}});this.observer.observe(canvas);
  this.refreshHUD();this.raf=requestAnimationFrame(this.loop);
 }
 configure(settings:SaveData['settings']){this.settings=settings;this.renderer.configure(settings);this.previousView='';if(settings.lowMotion&&this.travel)this.travel.duration=40;}
 pause(paused:boolean){this.paused=paused;this.last=0;if(this.directionPad)this.directionPad.inert=paused;if(paused)this.release();}
 destroy(){this.disposed=true;cancelAnimationFrame(this.raf);this.observer.disconnect();this.handlers.forEach(fn=>fn());this.directionPad?.remove();window.removeEventListener('pointerup',this.release);window.removeEventListener('pointercancel',this.release);window.removeEventListener('keydown',this.onKeyDown);window.removeEventListener('keyup',this.onKeyUp);window.removeEventListener('blur',this.release);}
 private release=()=>{this.held=null;};
 toggleMovementMode(){if(this.paused||this.model.state.completed)return;this.rolling=!this.rolling;this.refreshHUD();this.say(this.rolling?'变成蘑菇球，一格一格滚过去。':'恢复行走，沿着石砖慢慢探索。');}
 sow(){if(this.paused||this.travel||this.model.state.completed)return;const choices=this.world.actions();if(choices.length===1)this.perform(choices[0].id);else{this.say(choices.length?'在右侧选择机关的方向或落点。':'走到花床旁边的一格，再按 E 播种或互动。');document.querySelector<HTMLButtonElement>('[data-puzzle-action]')?.focus();}}
 private perform(action:string){
  if(this.paused||this.travel||this.model.state.completed)return;
  if(action==='replay'){this.clueUntil=this.clock+6500;this.say('跟着星座亮起的先后顺序，再点亮它们。');this.refreshHUD();return;}
  const from={...this.world.point};const count=this.model.state.collected.length;const result=this.world.act(action,this.clock,this.settings.lowMotion);this.say(result.message);
  if(!result.ok)return;
  this.characterAction={kind:action==='light'?'symbiosis':action.startsWith('note:')?'note':action.startsWith('choose:')&&this.model.current.mechanism!=='water'?'interact':'sow',startedAt:this.clock};
  this.sound(action.startsWith('note:')?action.split(':')[1] as SoundKind:'grow');
  if(result.jumped){this.route=[];this.characterAction=null;this.beginTravel(from,{...this.world.point},true,true);}
  if(this.model.state.collected.length>count)this.sound('collect');if(this.settings.vibration)navigator.vibrate?.(16);this.changed();
 }
 undo(){if(this.paused||this.model.state.completed)return;this.route=[];this.travel=null;this.held=null;this.characterAction=null;if(this.world.undo()){this.say('回到上一格，微光还在。');this.changed();}else this.say('还没有需要退回的脚步。');}
 hint(){const hint=this.model.hint();this.hintNode=hint.node;this.say(hint.message);}
 walkTo(id:string){const point=this.world.layout.nodes[id];if(point)this.walkToTile(point);}
 private walkToTile(position:GridPosition){
  if(this.paused||this.travel||this.model.state.completed)return;
  if(sameTile(position,this.world.position)){this.sow();return;}
  const route=this.world.pathTo(position);
  if(!route){this.hint();return;}
  this.route=route;this.target=position;this.hintNode=undefined;this.characterAction=null;this.advance();
 }
 step(direction:GridDirection){
  this.lastDirection=direction;
  if(this.paused||this.travel||this.model.state.completed)return;
  this.route=[];this.target=null;this.characterAction=null;
  const next=this.world.destination(direction);
  if(!next){this.blockedUntil=this.clock+220;this.say(this.world.destination(direction,true)?'前面有缺口，按空格 / J 或点击跳跃。':'这里没有通路，换个方向试试。');return;}
  this.beginTravel({...this.world.point},{...this.world.layout.tiles.get(gridKey(next))!},false);
 }
 jump(){
  if(this.paused||this.travel||this.model.state.completed)return;
  this.route=[];this.target=null;this.characterAction=null;
  const choices=this.world.actions().filter(a=>a.id.startsWith('jump:'));
  if(choices.length){const d=GRID_DIRECTIONS[this.lastDirection];const ranked=choices.map(a=>{const p=this.world.layout.nodes[a.id.slice(5)];const dx=p.x-this.world.position.x,dz=p.z-this.world.position.z;return {a,score:(dx*d.x+dz*d.z)/Math.hypot(dx,dz)};}).sort((a,b)=>b.score-a.score);this.perform(ranked[0].a.id);return;}
  const next=this.world.destination(this.lastDirection,true);
  if(!next){this.say('前方没有安全落脚的格子，先调整方向。');return;}
  this.beginTravel({...this.world.point},{...this.world.layout.tiles.get(gridKey(next))!},true);
 }
 private beginTravel(from:GridPoint,to:GridPoint,jump:boolean,landed=false){
  if(to.x===from.x&&to.z!==from.z)this.lastDirection=to.z>from.z?'down':'up';
  else if(to.z===from.z&&to.x!==from.x)this.lastDirection=to.x>from.x?'right':'left';
  const a=projectTile(from,this.renderer.view),b=projectTile(to,this.renderer.view);this.facing=facingFor(b.x-a.x,b.y-a.y);
  if(this.clock-this.lastWalkEnd>300)this.motionStartedAt=this.clock;
  this.travel={from,to,progress:0,jump,landed,startedAt:this.clock,duration:this.settings.lowMotion?36:jump?620:this.rolling?140:WALK_TILE_MS};this.sound('move');
 }
 private advance(){if(this.travel||this.paused||this.model.state.completed)return;const next=this.route.shift();if(!next)return;
  if(!(next.jump?this.world.canJump(next.position):this.world.canStep(next.position))){this.route=[];return;}
  this.beginTravel({...this.world.point},{...this.world.layout.tiles.get(gridKey(next.position))!},next.jump);
 }
 private onKeyDown=(event:KeyboardEvent)=>{
  if(this.paused||event.ctrlKey||event.metaKey||event.altKey||(event.target instanceof HTMLElement&&event.target.matches('input,select,textarea')))return;
  const key=event.key.toLowerCase();const dirs:Record<string,GridDirection>={arrowup:'up',w:'up',arrowdown:'down',s:'down',arrowleft:'left',a:'left',arrowright:'right',d:'right'};
  if(dirs[key]){event.preventDefault();this.held=dirs[key];this.lastDirection=this.held;this.route=[];if(!event.repeat)this.step(this.held);return;}
  if(event.repeat)return;
  if(key==='e'){event.preventDefault();this.sow();return;}
  if(key==='j'||event.code==='Space'){
   event.preventDefault();this.jump();return;
  }
  if(/^[1-4]$/.test(key)){const choice=this.world.actions()[Number(key)-1];if(choice){event.preventDefault();this.perform(choice.id);}}
 };
 private onKeyUp=(event:KeyboardEvent)=>{if(['arrowup','w','arrowdown','s','arrowleft','a','arrowright','d'].includes(event.key.toLowerCase()))this.held=null;};
 private buildTileControls(){
  const root=document.getElementById('gridControls');if(!root)return;
  root.innerHTML=[...this.world.layout.tiles.values()].filter(t=>!t.solid&&!t.gap).map(tile=>{
   const node=this.model.level.nodes.find(n=>sameTile(this.world.layout.nodes[n.id],tile));
   return `<button class="grid-tile-hit ${node?'grid-marker-hit':''}" data-grid-tile="${tile.key}" ${node?`data-node="${node.id}"`:''} aria-label="${node?node.label:`石砖 ${tile.x+1}, ${tile.z+1}`}" tabindex="${node?0:-1}"></button>`;
  }).join('');
 }
 private changed(){this.refreshHUD();this.onChange(this.model.snapshot());this.previousView='';}
 private refreshHUD(){
  const count=document.getElementById('sporeCount');if(count)count.textContent=`${this.model.state.collected.length} / ${totalSpores(this.model.level)}`;
  const grown=document.getElementById('grownCount');if(grown)grown.textContent=`${this.model.awakened} / ${this.model.level.nodes.filter(n=>n.mechanism).length}`;
  const undo=document.querySelector<HTMLButtonElement>('[data-action="撤销"]');if(undo)undo.disabled=!this.model.canUndo;
  const choices=this.world.actions();const primary=document.querySelector<HTMLButtonElement>('[data-action="播种"]');const label=choices.length===1?`${choices[0].label} · E`:choices.length?'选择机关用法':'播种 / 互动';
  primary?.setAttribute('aria-label',label);primary?.querySelector('[data-action-label]')?.replaceChildren(label);
  const mode=document.querySelector<HTMLButtonElement>('[data-action="切换移动"]');if(mode){mode.setAttribute('aria-pressed',String(this.rolling));mode.setAttribute('aria-label',this.rolling?'切换为行走':'切换为滚动');mode.querySelector('span')?.replaceChildren(this.rolling?'滚动中':'行走');}
  document.querySelector('.journey-toolbar')?.classList.toggle('is-rolling',this.rolling);
  const panel=document.getElementById('puzzlePanel');
  if(panel){const clue=this.model.level.sequence&&this.clock<this.clueUntil&&this.settings.lowMotion?this.model.level.sequence.map(id=>this.model.label(id)).join(' → '):'';
   panel.innerHTML=`<div class="puzzle-state"><strong>${this.model.level.kind}</strong><span>${clue||this.model.status()}</span><span id="beatStatus"></span></div><p class="grid-mechanic-copy">${this.model.level.subtitle}</p><div class="puzzle-actions">${choices.map((choice,i)=>`<button data-puzzle-action="${choice.id}" ${choice.selected===undefined?'':`aria-pressed="${choice.selected}"`}><small>${i+1}</small> ${choice.label}</button>`).join('')}${this.model.level.sequence?'<button data-puzzle-action="replay">重看星图 ↻</button>':''}</div>${!choices.length?'<div class="grid-plant-guide"><img src="./images/production/soil.png" alt="干涸的土地"/><span>→</span><img src="./images/reference-scenes/plant-bloom.png" alt="唤醒的花朵"/></div><small class="grid-help-copy">沿石砖走近植物，按 E 互动。<br>方向键逐格走，空格 / J 跳跃。</small>':''}`;
  }
  for(const button of document.querySelectorAll<HTMLButtonElement>('[data-node]')){
   const node=this.model.level.nodes.find(n=>n.id===button.dataset.node)!;const here=this.world.atNode(node.id);
   button.setAttribute('aria-current',here?'location':'false');button.setAttribute('aria-label',`${node.label}${here?'，当前位置，点击互动':'，点击逐格前往'}${this.model.isActive(node.id)?'，已唤醒':''}${node.spore&&!this.model.state.collected.includes(node.id)?'，有孢子':''}`);
  }
  this.canvas.dataset.gridX=String(this.world.position.x);this.canvas.dataset.gridZ=String(this.world.position.z);
 }
 private updateTileControls(){
  const v=this.renderer.view;const stamp=`${v.originX.toFixed(1)}:${v.originY.toFixed(1)}:${v.scale}:${this.model.state.node}:${this.model.state.activated.join(',')}:${JSON.stringify(this.model.state.vars)}:${this.model.state.buddy}`;
  if(stamp===this.previousView)return;this.previousView=stamp;
  for(const button of document.querySelectorAll<HTMLButtonElement>('[data-grid-tile]')){const tile=this.world.layout.tiles.get(button.dataset.gridTile!)!;const p=projectTile(tile,v);const marker=!!button.dataset.node;
   button.hidden=!this.world.tileVisible(tile)||!this.world.ownerOpen(tile)||p.x<-30||p.x>v.width+30||p.y<-10||p.y>v.height+30;
   const width=v.tileWidth*v.scale,height=(marker?105:v.tileHeight+5)*v.scale;
   button.style.left=`${p.x-width/2}px`;button.style.top=`${p.y-(marker?80:v.tileHeight/2)*v.scale}px`;button.style.width=`${width}px`;button.style.height=`${height}px`;
  }
 }
 private say(message:string){if(message&&this.tip)this.tip.textContent=message;}
 private loop=(time:number)=>{
  if(this.disposed)return;const dt=this.last?Math.min(50,time-this.last):0;this.last=time;
  if(!this.paused&&!document.hidden){
   this.clock+=dt;
   if(this.travel){this.travel.progress=Math.min(1,this.travel.progress+dt/this.travel.duration);
    if(this.travel.progress===1){const travel=this.travel;const previous=this.model.state.collected.length;const result=travel.landed?{ok:true,message:'睡莲接住了你的选择。'}:this.world.commit(travel.to,travel.jump);this.travel=null;this.lastWalkEnd=this.clock;
     if(result.ok){if(this.model.state.collected.length>previous)this.sound('collect');this.changed();if(result.message)this.say(result.message);}
     else{this.route=[];this.say(result.message);}
     if(this.model.state.completed&&!this.reported){this.reported=true;this.held=null;this.route=[];this.sound('complete');this.complete({completed:true,levelId:this.model.level.id,seeds:this.model.level.nodes.filter(n=>n.mechanism).map(n=>!!this.model.isActive(n.id)),collected:this.model.state.collected.length,total:totalSpores(this.model.level),stars:this.model.stars,awakened:this.model.awakened});}
     else this.advance();
    }
   }else if(this.held&&this.clock>this.blockedUntil)this.step(this.held);else this.advance();
  }
  let player={...this.world.point};
  if(this.travel){const p=this.travel.progress;player={x:this.travel.from.x+(this.travel.to.x-this.travel.from.x)*p,z:this.travel.from.z+(this.travel.to.z-this.travel.from.z)*p,h:this.travel.from.h+(this.travel.to.h-this.travel.from.h)*p};}
  const pose=characterPose({time:this.clock,facing:this.facing,lowMotion:this.settings.lowMotion,complete:this.model.state.completed&&!this.travel,travel:this.travel?{progress:this.travel.progress,startedAt:this.travel.jump?this.travel.startedAt:this.motionStartedAt,jump:this.travel.jump,rolling:this.rolling,distance:Math.hypot(this.travel.to.x-this.travel.from.x,this.travel.to.z-this.travel.from.z)*55}:null,action:this.characterAction});
  this.canvas.dataset.characterClip=pose.clip;this.canvas.dataset.characterFrame=pose.key;this.canvas.dataset.characterFacing=this.facing;this.canvas.dataset.moving=String(!!this.travel);
  document.querySelector('.journey-toolbar')?.classList.toggle('is-interacting',['sow','interact','symbiosis'].includes(pose.clip));
  this.renderer.draw({time:this.clock,player,pose,travel:this.travel,hint:this.hintNode,target:this.target,clueUntil:this.clueUntil,actionElapsed:this.characterAction?this.clock-this.characterAction.startedAt:undefined});this.updateTileControls();
  const beat=document.getElementById('beatStatus');if(beat&&this.model.level.melody){const open=this.settings.lowMotion||this.clock%2400<1200;beat.textContent=open?'● 水膜亮起':'○ 等下一拍';beat.classList.toggle('beat-open',open);}
  this.raf=requestAnimationFrame(this.loop);
 };
}
