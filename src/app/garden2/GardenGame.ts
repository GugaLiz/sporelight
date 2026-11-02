import {GardenWorld} from './world';
import {drawMushroomBuddy} from '../game/mushroomBuddy';
import {WALK_TILE_MS} from '../game/characterMotion';
import {GardenRenderer,type Motion} from './render';
import {DIRECTION,type GardenState,type Actor} from './types';
import type {SaveData,GameSnapshot} from '../types';
import type {SoundKind} from '../game/audio';
import {escapeHtml} from '../ui';
export class GardenGame{
 readonly model:GardenWorld;readonly renderer:GardenRenderer;
 private root:HTMLElement;private frame=0;private observer:ResizeObserver;private paused=false;private disposed=false;private time=0;private last=0;private beatClock=0;
 private route:string[]=[];private motion?:Motion;private pending?:{kind:'move'|'act';value:string};private elapsed=0;private hintUntil=0;private messageText='';private strolling=false;private rolling=false;private waitingRepair=false;
 private lastDirection='right';private hopping=false;
 private walkStartedAt=0;private lastWalkEnd=-1000;
 private targetsMarkup='';
 private growthHint=false;
 constructor(canvas:HTMLCanvasElement,id:string,saved:GardenState|undefined,private settings:SaveData['settings'],private onChange:(state:GardenState)=>void,private complete:(result:GameSnapshot)=>void,private sound:(kind:SoundKind)=>void){
  this.model=new GardenWorld(id,saved);this.renderer=new GardenRenderer(canvas,this.model,settings);this.root=canvas.closest<HTMLElement>('.garden-game')!;this.root.dataset.level=id;this.root.dataset.dual=String(this.model.level.dual);this.root.dataset.chapter=this.model.level.chapter;
  this.root.querySelector('.garden-heading small')!.textContent=`${({valley:'苔藓山谷',pond:'雨滴池塘',cave:'星光洞穴'})[this.model.level.chapter]} · 关卡 2.0`;
  const portrait=this.root.querySelector<HTMLCanvasElement>('[data-buddy-portrait]')!;drawMushroomBuddy(portrait.getContext('2d')!,48,104,96,0,{lowMotion:true});
  this.root.querySelector('#gardenTitle')!.textContent=`${id} · ${this.model.level.title}`;this.root.querySelector('#gardenRule')!.textContent=this.model.level.rule;
  this.message(this.model.level.intro);this.root.addEventListener('click',this.click);window.addEventListener('keydown',this.key);
  this.observer=new ResizeObserver(()=>{this.renderer.resize();if(this.growthHint&&this.renderer.width<650&&!this.model.connected())this.renderer.overview=true;this.draw();this.targets();});this.observer.observe(canvas);
  this.draw();this.ui();this.saved();if(this.model.state.completed)this.ending();this.frame=requestAnimationFrame(this.loop);
 }
 private message(s:string){this.messageText=s;this.root.querySelector('#gardenMessage')!.textContent=s;}
 private click=(event:MouseEvent)=>{const b=(event.target as HTMLElement).closest<HTMLButtonElement>('button');if(!b)return;
  if(b.dataset.gardenTile)this.go(b.dataset.gardenTile);
  if(b.dataset.gardenDo)this.act(b.dataset.gardenDo);
  if(b.dataset.gardenDir)this.step(b.dataset.gardenDir);
  if(b.dataset.gardenActor&&b.dataset.gardenActor!==this.model.actor)this.act('switch');
  if(b.hasAttribute('data-garden-follow'))this.act('follow');
  if(b.hasAttribute('data-growth-guide')){const guide=this.model.growthGuidance();if(guide){if(this.model.actor!=='luvie')this.act('switch');this.go(guide.root.at);}}
  if(b.id==='gardenOverview'){this.renderer.overview=!this.renderer.overview;this.draw();this.targets();}
  if(b.id==='gardenStay'){this.root.querySelector<HTMLElement>('#gardenEnding')!.hidden=true;this.strolling=true;this.message('留下走走，坐一会儿。已经修复的花园会在纪事里等你。');this.ui();}
 };
 private key=(e:KeyboardEvent)=>{
  if(this.paused||this.disposed||e.ctrlKey||e.metaKey||e.altKey||['INPUT','TEXTAREA','SELECT'].includes((e.target as HTMLElement)?.tagName))return;
  const dir=({ArrowUp:'up',ArrowRight:'right',ArrowDown:'down',ArrowLeft:'left',w:'up',d:'right',s:'down',a:'left'} as Record<string,string>)[e.key];
  if(dir){e.preventDefault();if(!e.repeat)this.step(dir);return;}
  const key=e.key.toLowerCase();if(key==='e'){e.preventDefault();this.sow();}if(key==='t'){e.preventDefault();this.act('switch');}if(key==='z'){e.preventDefault();this.undo();}if(key==='h'){e.preventDefault();this.hint();}
  if(e.code==='Space'||key==='j'){e.preventDefault();this.jump();}
  if(/^[1-9]$/.test(key)){const c=this.localCommands()[+key-1];if(c){e.preventDefault();this.act(c.id);}}
 };
 private localCommands(){return this.model.commands().filter(c=>!['switch','follow'].includes(c.id));}
 private locked(){return this.paused||!!this.motion||this.model.state.completed&&!this.strolling;}
 private go(id:string){if(this.locked()||this.model.state.playing)return;const path=this.model.pathTo(id);if(!path){this.message('这段路还没接上，看看高度、角色能力与庭院出口。');return;}this.route=path;this.advance();}
 private advance(){if(this.locked())return;const id=this.route.shift();if(id)this.start('move',id);}
 private step(dir:string){if(this.locked()||this.model.state.playing)return;this.lastDirection=dir;this.route=[];const p=this.model.point,[x,z]=DIRECTION[dir as keyof typeof DIRECTION];const t=this.model.neighbors(p.id).find(t=>t.x===p.x+x&&t.z===p.z+z);if(t)this.start('move',t.id);else this.message('这里尚未连通。不同高度和低拱，也会改变谁能通过。');}
 private act(id:string){if(this.locked())return;this.route=[];if(id==='repair'&&!this.model.together&&this.model.state.follow&&this.model.commands().some(c=>c.id==='rejoin')){this.waitingRepair=true;this.start('act','rejoin');return;}this.start('act',id);}
 private start(kind:'move'|'act',value:string){
  const before=this.model.snapshot(),test=new GardenWorld(this.model.level.id,before),result=kind==='move'?test.move(value):test.act(value,value==='beat'&&before.playing);
  if(!result.ok){this.waitingRepair=false;if(value==='repair'&&this.model.level.id==='1-2'&&!this.model.connected())this.showGrowthHint();else this.message(result.message);return;}
  if(JSON.stringify(before)===JSON.stringify(test.snapshot())){this.message(result.message);return;}
  const to=test.snapshot(),clip=kind==='move'?(this.hopping?'hop':this.rolling?'roll':'move'):value;
  if(['move','rejoin'].includes(clip)&&before.actors.luvie!==to.actors.luvie&&this.time-this.lastWalkEnd>300)this.walkStartedAt=this.time;
  this.motion={from:before,to,progress:0,kind:clip,startedAt:this.time,walkStartedAt:this.walkStartedAt,duration:['move','rejoin'].includes(clip)?WALK_TILE_MS:clip==='roll'?155:clip==='hop'?620:780};this.hopping=false;this.pending={kind,value};this.elapsed=0;this.message(result.message);
  if(this.settings.lowMotion||value==='switch'||value==='follow'||value.startsWith('swap:')||value==='play')this.finish();else this.ui();
 }
 private finish(){const p=this.pending;if(!p)return;const wasCompleted=this.model.state.completed;const result=p.kind==='move'?this.model.move(p.value):this.model.act(p.value,p.value==='beat'&&this.model.state.playing);if(this.motion&&['move','rejoin'].includes(this.motion.kind)&&this.motion.from.actors.luvie!==this.motion.to.actors.luvie)this.lastWalkEnd=this.time;this.motion=undefined;this.pending=undefined;
  if(!result.ok){this.route=[];this.message(result.message);}else{this.message(result.message);this.sound(p.kind==='move'?'move':p.value==='repair'?'complete':p.value.startsWith('take:')?'collect':'grow');this.saved();}
  this.draw();this.ui();if(result.ok&&!wasCompleted&&this.model.state.completed){this.complete(this.snapshot());this.ending();}
  if(this.waitingRepair){if(!result.ok){this.waitingRepair=false;}else if(this.model.together){this.waitingRepair=false;this.start('act','repair');}else if(this.model.commands().some(c=>c.id==='rejoin'))this.start('act','rejoin');else this.waitingRepair=false;}
  if(!this.waitingRepair&&this.route.length&&!this.settings.lowMotion)this.advance();
 }
 private saved(){this.onChange(this.model.snapshot());}
 private snapshot():GameSnapshot{const s=this.model.state,total=this.model.level.total,n=s.collected.length;return{completed:s.completed,levelId:s.levelId,seeds:s.flags.map(()=>true),collected:n,total,stars:n>=total?3:n>=Math.ceil(total/2)?2:1,awakened:s.flags.length};}
 sow(){if(this.locked())return;const c=this.localCommands(),primary=c.find(a=>a.id==='repair')??c.find(a=>a.id.startsWith('take:'))??c.find(a=>a.id!=='rejoin');if(primary)this.act(primary.id);else this.message('走近根台、物件或庭院中心，再看看能做什么。');}
 undo(){if(this.paused||this.motion)return;this.route=[];if(this.model.undo()){this.saved();this.root.querySelector<HTMLElement>('#gardenEnding')!.hidden=true;this.message('回到刚才的稳定时刻，再试一种安排。');this.draw();this.ui();}}
 hint(){if(this.paused||this.motion)return;if(this.model.level.id==='1-2'&&!this.model.connected())this.showGrowthHint();else{this.hintUntil=this.time+12000;this.message(this.model.hint().message);}this.sound('叮');}
 private showGrowthHint(){this.growthHint=true;if(this.renderer.width<650)this.renderer.overview=true;const g=this.model.growthGuidance();this.message(g?.retract?'这段根线需要调整：先回发光的根台，收回最后一节，再跟随箭头。':this.model.near(this.model.level.roots[0].at)?'点击地图上发光的＋，让根须沿箭头长出下一节；最后一节也要接入花床。':'根线还没接入花床。先回地图上标出的根台，再点击发光的＋补齐。');this.draw();this.targets();}
 jump(){if(this.locked()||this.model.state.playing)return;this.route=[];const p=this.model.point,[dx,dz]=DIRECTION[this.lastDirection as keyof typeof DIRECTION],tile=this.model.neighbors(p.id).find(t=>t.x===p.x+dx&&t.z===p.z+dz);if(tile){this.hopping=true;this.start('move',tile.id);}else{const s=this.model.snapshot();this.motion={from:s,to:s,progress:0,kind:'jump',startedAt:this.time,walkStartedAt:this.time,duration:620};this.elapsed=0;this.ui();}}
 toggleMovementMode(){if(this.locked())return;this.rolling=!this.rolling;this.message(this.rolling?'变成蘑菇球，沿接通的石板轻轻滚动。':'站起来，和伙伴慢慢走。');this.ui();}
 pause(v:boolean){this.paused=v;this.last=0;this.ui();}
 configure(s:SaveData['settings']){this.settings=s;this.renderer.configure(s);if(s.lowMotion&&this.motion)this.finish();this.draw();this.ui();}
 private draw(){this.renderer.draw(this.time,this.motion,this.hintUntil>this.time||(this.growthHint&&!this.model.connected()));}
 private ui(){
  const s=this.model.state,commands=this.model.commands(),locked=!!this.motion||this.paused;
  this.root.querySelector('#gardenCommands')!.innerHTML=commands.filter(c=>c.id!=='switch').map((c,i)=>`<button data-garden-do="${escapeHtml(c.id)}" ${locked?'disabled':''} ${c.selected===undefined?'':`aria-pressed="${c.selected}"`}>${escapeHtml(c.label)}</button>`).join('');
  this.root.querySelectorAll<HTMLButtonElement>('[data-garden-actor]').forEach(b=>{b.disabled=locked||!this.model.level.dual||s.completed&&!this.strolling;b.setAttribute('aria-pressed',String(s.active===b.dataset.gardenActor));});
  const follow=this.root.querySelector<HTMLButtonElement>('[data-garden-follow]')!;follow.disabled=locked||!this.model.level.dual||s.completed&&!this.strolling;follow.setAttribute('aria-pressed',String(s.follow));follow.setAttribute('aria-label',s.follow?'关闭自动同行，伙伴会在当前位置等候':'开启自动同行，伙伴会沿路跟随');follow.title=s.follow?'伙伴会沿接通的路跟随':'伙伴会在当前位置等候';follow.textContent=s.follow?'同行':'等候';
  const carried=Object.entries(s.items).find(([,i])=>i.holder===s.active);
  this.root.querySelector('#gardenStatus')!.textContent=`${s.active==='luvie'?'露薇':'小苔灵'}${carried?` · 带着${carried[0].startsWith('mirror')?'镜叶':carried[0].endsWith('Post')?'日月影柱':carried[0]==='lamp'?'暖灯':carried[0]==='dew'?'清露':'门铃'}`:''}${this.model.level.roots.length?` · 芽节余${this.model.budget}`:''}${this.model.level.id==='2-3'?` · ${s.song.map(n=>({turn:'转庭',rise:'升台',rest:'停拍'})[n]).join(' → ')} · ${s.beat}/3拍`:''}`;
  this.root.querySelector('#gardenCount')!.textContent=`${s.collected.length} / ${this.model.level.total}`;
  if(this.model.level.id==='2-1')this.root.querySelector('#gardenRule')!.textContent=`${['低','中','高'][s.water]}水位 · ${['浅湾踏石露出水面','花台与花岸平齐','花台与芦苇高岸平齐'][s.water]}`;
  if(this.model.level.id==='1-4')this.root.querySelector('#gardenRule')!.textContent=this.model.flag('home')?'花门已打开 · 接上伙伴，去小花园中央播种':this.model.level.rule;
  if(this.model.level.id==='1-2')this.root.querySelector('#gardenRule')!.textContent=`根线 ${s.growth.root.length} / 4 节 · 点地图上的＋引芽，最后接入花床`;
  this.root.querySelector('#gardenGoal')!.textContent=s.completed?this.model.level.story:this.model.ready()?'花园已连通，带同伴到核心种下微光。':'把路、生命与同伴连接起来，再照料核心。';
  if(this.model.level.id==='3-4'&&!s.completed)this.root.querySelector('#gardenGoal')!.textContent=`叶${this.model.flag('root')?'✓':'○'} · 雨${this.model.flag('rain')?'✓':'○'} · 星${this.model.flag('star')?'✓':'○'} · 月${this.model.flag('moon')?'✓':'○'}。当前连接：水${s.turns.water===1?'✓':'○'}、光${this.model.beamHits(-4,0)?'✓':'○'}、归途${s.turns.inner===1?'✓':'○'}。两位会合后，一起播种。`;
  const c=this.renderer.canvas;c.dataset.level=s.levelId;c.dataset.actor=s.active;c.dataset.tile=s.actors[s.active];c.dataset.moving=String(!!this.motion);c.dataset.completed=String(s.completed);c.dataset.beat=String(s.beat);
  this.root.querySelectorAll<HTMLButtonElement>('[data-garden-dir]').forEach(b=>b.disabled=locked||s.completed&&!this.strolling);
  this.root.querySelector<HTMLButtonElement>('[data-action="撤销"]')!.disabled=locked||!this.model.canUndo;
  const primary=this.localCommands().find(c=>c.id==='repair')??this.localCommands().find(c=>c.id.startsWith('take:'))??this.localCommands().find(c=>c.id!=='rejoin');this.root.querySelector('[data-garden-primary-label]')?.replaceChildren(primary?`${primary.label} · E`:'播种 / 互动 · E');this.root.querySelector('[data-garden-mode-label]')?.replaceChildren(this.rolling?'滚动中':'行走');
  this.targets();
 }
 private targets(){
  const model=this.model,r=this.renderer,commands=model.commands();let html='';
  for(const t of model.tiles){if(t.solid||!model.visible(t))continue;const p=r.project(t);if(p.x<-40||p.x>r.width+40||p.y<-40||p.y>r.height+40)continue;const mark=model.level.marks.find(m=>m.tile===t.id);const w=70*r.scale,h=35*r.scale;html+=`<button class="garden-tile ${mark?'garden-mark-hit':''}" data-garden-tile="${t.id}" ${mark?`data-garden-mark="${mark.id}"`:''} ${this.locked()?'disabled':''} aria-label="${escapeHtml(mark?.label??(t.kind==='water'?'走到浅水中的踏石':'走到这块石板'))}" ${t.id===model.state.actors[model.actor]?'aria-current="location"':''} style="left:${p.x-w/2}px;top:${p.y-(mark?43*r.scale:h/2)}px;width:${Math.max(mark?36:0,w)}px;height:${mark?Math.max(44,65*r.scale):h}px"></button>`;}
  for(const cmd of commands)if(cmd.target){const match=/:(-?\d+):(-?\d+)$/.exec(cmd.target)!;const p=r.project({x:+match[1],z:+match[2],h:model.level.roots[0].h});html+=`<button class="garden-grow-hit" data-garden-do="${cmd.id}" ${this.motion||this.paused?'disabled':''} aria-label="${escapeHtml(cmd.label)}" style="left:${p.x-22}px;top:${p.y-22}px;width:44px;height:44px">＋</button>`;}
  const guide=model.level.id==='1-2'&&!model.state.completed?model.growthGuidance():undefined;
  if(guide&&(this.growthHint||!model.connected())&&!model.near(guide.root.at)){const p=r.project(guide.origin);html+=`<button class="garden-growth-return" data-growth-guide ${this.locked()?'disabled':''} aria-label="返回根台继续引芽" style="left:${p.x-52}px;top:${p.y-70*r.scale}px;width:104px;height:44px">回根台引芽</button>`;}
  for(const [id,item]of Object.entries(model.state.items))if(!item.holder&&item.tile&&id!=='bug'){const tile=model.tiles.find(t=>t.id===item.tile);if(!tile||!model.visible(tile))continue;const p=r.project(tile);html+=`<button class="garden-item-hit" data-garden-tile="${item.tile}" data-garden-item="${id}" ${this.locked()?'disabled':''} aria-label="走近${id.startsWith('mirror')?'反光叶':id.endsWith('Post')?'日月影柱':id==='lamp'?'暖灯':id==='dew'?'清露':'门铃'}" style="left:${p.x-22}px;top:${p.y-35*r.scale}px;width:44px;height:44px"></button>`;}
  if(html!==this.targetsMarkup){this.root.querySelector('#gardenTargets')!.innerHTML=html;this.targetsMarkup=html;}
 }
 private ending(){const el=this.root.querySelector<HTMLElement>('#gardenEnding')!;el.hidden=false;el.querySelector('h2')!.textContent='这里，又可以成为家。';el.querySelector('p')!.textContent=this.model.level.story;el.querySelector<HTMLButtonElement>('[data-action="下一关"]')!.textContent=this.model.level.id==='3-4'?'看看一路的纪事 ↗':'去下一片微光 ↗';}
 private loop=(now:number)=>{
  if(this.disposed)return;const dt=this.last?Math.min(50,now-this.last):0;this.last=now;
  if(!this.paused&&!document.hidden){this.time+=dt;if(this.motion){this.elapsed+=dt;this.motion.progress=Math.min(1,this.elapsed/this.motion.duration);if(this.motion.progress>=1){if(this.motion.kind==='jump'){this.motion=undefined;this.ui();}else this.finish();}}
   else if(this.route.length)this.advance();
   else if(this.model.state.playing){this.beatClock+=dt;if(this.beatClock>600){this.beatClock=0;this.start('act','beat');}}
  }
  this.draw();this.targets();this.frame=requestAnimationFrame(this.loop);
 };
 destroy(){this.disposed=true;cancelAnimationFrame(this.frame);this.observer.disconnect();this.root.removeEventListener('click',this.click);window.removeEventListener('keydown',this.key);}
}
