import { CLOUD_LEVELS, type CloudLevelId } from './data';
import { CloudModel, type CloudSave } from './model';
import { CloudRenderer, type CloudAnimation } from './renderer';
import type { SaveData } from '../types';
import type { SoundKind } from '../game/audio';
import { escapeHtml, materialIcon } from '../ui';
const directions:Record<string,[number,number]>={up:[0,-1],down:[0,1],left:[-1,0],right:[1,0]};
export class CloudGame {
  readonly model:CloudModel;
  readonly renderer:CloudRenderer;
  private frame=0;private previousTime=0;private animation?:CloudAnimation;private elapsed=0;
  private route:string[]=[];private paused=false;private destroyed=false;
  private pose='idle';private poseUntil=0;private hintTarget?:string;private hintUntil=0;
  private review:boolean;private ambientAt=0;private sceneTime=0;
  private observer:ResizeObserver;
  private el:HTMLElement;
  constructor(canvas:HTMLCanvasElement,id:CloudLevelId,private save:CloudSave,private settings:SaveData['settings'],private persist:()=>void,private next:(id:CloudLevelId)=>void,private sound:(kind:SoundKind)=>void,review=false){
    this.review=review;this.model=new CloudModel(id,review?save.memories[id]??{version:1,levelId:id,repaired:true,bridge:id==='cloud-1'?'east':'north',lift:'high'}:save.runs[id]);
    if(review){this.model.state.repaired=true;this.model.state.buddy='sit';}
    this.el=canvas.closest<HTMLElement>('.cloud-game')!;
    this.renderer=new CloudRenderer(canvas,this.model,settings);
    this.observer=new ResizeObserver(()=>this.resize());this.observer.observe(canvas);
    this.el.querySelector('#cloudTitle')!.textContent=this.model.level.title;
    this.el.querySelector('#cloudSubtitle')!.textContent=this.model.level.subtitle;
    this.el.querySelector('#cloudChapterNumber')!.textContent=` / 0${CLOUD_LEVELS.findIndex(l=>l.id===id)+1}`;
    this.el.style.setProperty('--cloud-accent',this.model.level.accent);
    this.message(review?this.model.level.restored:this.model.hint().message);
    this.el.addEventListener('click',this.click);
    window.addEventListener('keydown',this.key);window.addEventListener('resize',this.resize);
    this.updateUI();this.tick(0);
    if(this.model.state.repaired)this.showEnding();
  }
  private message(text:string){this.el.querySelector('#cloudMessage')!.textContent=text;}
  private click=(event:MouseEvent)=>{
    const target=(event.target as HTMLElement).closest<HTMLElement>('button');if(!target)return;
    if(target.dataset.cloudTile){this.go(target.dataset.cloudTile);return;}
    if(target.dataset.cloudDo){this.act(target.dataset.cloudDo);return;}
    if(target.dataset.cloudDirection){this.step(target.dataset.cloudDirection);return;}
    if(target.id==='cloudUndo')this.undo();
    if(target.id==='cloudHint')this.hint();
    if(target.id==='cloudStay'){this.el.querySelector<HTMLElement>('#cloudEnding')!.hidden=true;this.message('在这里坐一会儿。想离开时，打开右上角的庭院手册。');}
    if(target.id==='cloudNext'){const index=CLOUD_LEVELS.findIndex(l=>l.id===this.model.id);if(CLOUD_LEVELS[index+1])this.next(CLOUD_LEVELS[index+1].id);}
  };
  private key=(event:KeyboardEvent)=>{
    if(this.paused||this.destroyed||event.ctrlKey||event.altKey||event.metaKey||['INPUT','TEXTAREA','SELECT'].includes((event.target as HTMLElement)?.tagName))return;
    const direction=({ArrowUp:'up',ArrowDown:'down',ArrowLeft:'left',ArrowRight:'right',w:'up',s:'down',a:'left',d:'right'} as Record<string,string>)[event.key];
    if(direction){event.preventDefault();this.step(direction);return;}
    if(event.key.toLowerCase()==='e'){event.preventDefault();const action=this.model.actions().find(a=>a.id!=='pet'&&a.id!=='call')??this.model.actions()[0];if(action)this.act(action.id);}
    if(event.key.toLowerCase()==='z'){event.preventDefault();this.undo();}
    if(event.key.toLowerCase()==='h'){event.preventDefault();this.hint();}
  };
  private step(direction:string){
    if(this.paused||this.animation||this.model.state.repaired)return;
    this.route=[];const [dx,dz]=directions[direction],p=this.model.current;
    const dest=this.model.neighbors(p.id).find(t=>t.x===p.x+dx&&t.z===p.z+dz);
    if(dest)this.walk(dest.id);else this.message('这边没有接上的路。看看桥的朝向和花台的高度吧。');
  }
  private go(id:string){
    if(this.paused||this.animation||this.model.state.repaired)return;
    const path=this.model.pathTo(id);if(!path){this.message('这片庭院还没连上。先看看附近的机关吧。');return;}
    this.route=path;this.advance();
  }
  private advance(){if(this.paused||this.animation)return;const id=this.route.shift();if(id)this.walk(id);}
  private walk(id:string){
    const from=this.model.snapshot(),preview=new CloudModel(this.model.id,from);
    if(!preview.move(id)){this.route=[];return;}
    this.animation={from,to:preview.snapshot(),progress:0,kind:'walk'};this.elapsed=0;this.pose='walk';this.updateUI();
    if(this.settings.lowMotion)this.finishAnimation();
  }
  private act(id:string){
    if(this.paused||this.animation||this.model.state.repaired)return;this.route=[];
    const from=this.model.snapshot(),preview=new CloudModel(this.model.id,from),result=preview.act(id);
    if(!result.ok){this.message(result.message);return;}
    if(id==='rotate'||id==='lift'){
      this.animation={from,to:preview.snapshot(),progress:0,kind:id};this.elapsed=0;this.updateUI();
      if(this.settings.lowMotion)this.finishAnimation();
      return;
    }
    const committed=this.model.act(id);this.message(committed.message);this.hintTarget=undefined;
    if(id==='pet'||id==='wait'||id==='call'){this.pose=id==='pet'?'pet':'wave';this.poseUntil=performance.now()+1900;}
    this.sound(id==='repair'?'complete':id.startsWith('discover')?'collect':'grow');
    this.saved();this.updateUI();
    if(this.model.state.repaired){this.pose='happy';this.poseUntil=performance.now()+1800;this.showEnding();}
  }
  private finishAnimation(){
    const a=this.animation;if(!a)return;
    if(a.kind==='walk')this.model.move(a.to.tile);else{const result=this.model.act(a.kind);this.message(result.message);}
    this.animation=undefined;this.pose='idle';this.saved();this.updateUI();this.sound(a.kind==='walk'?'move':'grow');
    // Movement is resumed on the next animation frame so instant-motion mode cannot recurse.
  }
  private saved(){
    if(this.review)return;
    const id=this.model.id;this.save.lastLevel=id;this.save.runs[id]=this.model.snapshot();
    this.save.discoveries[id]=[...new Set([...(this.save.discoveries[id]??[]),...this.model.state.found])];
    if(this.model.state.repaired&&!this.save.completed.includes(id))this.save.completed.push(id);
    if(this.model.state.repaired)this.save.memories[id]=this.model.snapshot();
    this.persist();
  }
  private undo(){if(this.paused||this.animation||this.review)return;this.route=[];if(this.model.undo()){this.el.querySelector<HTMLElement>('#cloudEnding')!.hidden=true;this.saved();this.message('回到刚才那一刻。每一步，都可以慢慢试。');this.updateUI();}}
  private hint(){if(this.paused||this.animation)return;const h=this.model.hint();this.hintTarget=h.target;this.hintUntil=performance.now()+12000;this.message(h.message);this.sound('叮');}
  private updateUI(){
    const s=this.model.state,locked=this.paused||!!this.animation;
    this.el.classList.toggle('is-repaired',s.repaired);
    const objectives=this.model.id==='cloud-1'?[[s.seed,'去侧庭，找到一粒花种'],[s.bridge==='east','转动拱桥，连接钟塔'],[s.repaired,'在钟塔下种出第一朵花']]:this.model.id==='cloud-2'?[[s.lift==='high','乘着花台，来到高处'],[s.repaired,'引水入池，等小鸟归来']]:[[s.latch||s.buddy==='wait','请小苔灵守住叶形踏板'],[s.latch,'穿过拱廊，打开门闩'],[s.latch&&s.buddy!=='wait','回到踏板旁，接回伙伴'],[s.repaired,'一起点亮屋顶的星灯']];
    this.el.querySelector('#cloudObjectives')!.innerHTML=objectives.map(([done,label])=>`<li class="${done?'is-done':''}"><span>${done?'✓':'○'}</span>${label}</li>`).join('');
    this.el.querySelector('#cloudInventory')!.innerHTML=`${materialIcon('spore')}<span>${this.model.id==='cloud-1'?(s.seed?'口袋里有一粒花种':'花种还在等你'):'每一步，都算数'}</span>`;
    this.el.querySelector('#cloudCompanion')!.textContent=s.buddy==='sleep'?'一个小伙伴，正做着柔软的梦。':s.buddy==='wait'?'小苔灵在叶形踏板上等你。':s.repaired?'露薇与小苔灵，坐在微光里。':'小苔灵正跟着你。也可以摸摸它。';
    this.el.querySelector('#cloudExploration')!.innerHTML=`${materialIcon('leaf')}<span>口袋里的小事 <b>${s.found.length} / 2</b></span>`;
    this.el.querySelector<HTMLButtonElement>('#cloudUndo')!.disabled=locked||!this.model.canUndo||this.review;
    this.el.querySelector<HTMLButtonElement>('#cloudHint')!.disabled=locked||s.repaired;
    this.el.querySelectorAll<HTMLButtonElement>('[data-cloud-direction]').forEach(b=>b.disabled=locked||s.repaired);
    this.el.querySelector('#cloudLocalActions')!.innerHTML=this.model.actions().map(a=>`<button class="cloud-button ${a.id==='pet'?'cloud-pet':'cloud-primary'}" data-cloud-do="${a.id}" ${locked?'disabled':''}>${materialIcon(a.id==='repair'?'sow':a.id==='seed'?'spore':a.id==='rotate'?'retry':a.id.startsWith('discover:')?'gallery':'leaf')}<span>${escapeHtml(a.label)}</span>${a.id!=='pet'?'<small>E</small>':''}</button>`).join('');
    this.renderer.canvas.dataset.tile=s.tile;this.renderer.canvas.dataset.bridge=s.bridge;this.renderer.canvas.dataset.lift=s.lift;this.renderer.canvas.dataset.buddy=s.buddy;this.renderer.canvas.dataset.moving=String(!!this.animation);this.renderer.canvas.dataset.repaired=String(s.repaired);
    this.syncTiles();this.positionActions();
  }
  private syncTiles(){
    const controls=this.el.querySelector<HTMLElement>('#cloudTileControls')!;
    controls.innerHTML=this.model.tiles.map(t=>{const p=this.renderer.project(t),w=58*this.renderer.scale,h=29*this.renderer.scale;return `<button class="cloud-tile-hit" data-cloud-tile="${t.id}" aria-label="走到地块 ${t.x}, ${t.z}" ${this.paused||this.animation||this.model.state.repaired?'disabled':''} ${t.id===this.model.state.tile?'aria-current="location"':''} style="left:${p.x-w/2}px;top:${p.y-h/2}px;width:${w}px;height:${h}px"></button>`;}).join('');
    // Named landmark targets remain keyboard accessible and make small touch targets forgiving.
    for(const l of this.model.level.landmarks){const lp=this.model.landmarkPoint(l),tile=this.model.tiles.find(t=>t.x===lp.x&&t.z===lp.z&&t.h===lp.h);if(!tile)continue;const p=this.renderer.landmarkAnchor(lp),b=document.createElement('button');b.className='cloud-landmark-hit';b.dataset.cloudTile=tile.id;b.dataset.cloudLandmark=l.id;b.ariaLabel=`前往${l.label}`;b.disabled=this.paused||!!this.animation||this.model.state.repaired;b.style.cssText=`left:${p.x-22}px;top:${p.y-22}px;width:44px;height:44px`;controls.append(b);}
  }
  private positionActions(){
    const panel=this.el.querySelector<HTMLElement>('#cloudLocalActions')!;
    const p=this.renderer.project(this.model.current),portrait=this.renderer.width<650;
    panel.style.left=`${Math.max(portrait?12:225,Math.min(this.renderer.width-222,p.x+28))}px`;
    panel.style.top=`${Math.max(portrait?180:130,Math.min(this.renderer.height-(portrait?285:180),p.y-92))}px`;
  }
  private showEnding(){
    const ending=this.el.querySelector<HTMLElement>('#cloudEnding')!;ending.hidden=false;
    ending.querySelector('h2')!.textContent=this.model.level.restored;ending.querySelector('p')!.textContent=this.model.level.story;
    const next=ending.querySelector<HTMLButtonElement>('#cloudNext')!;next.hidden=this.model.id==='cloud-3'||this.review;
    if(!this.review)ending.querySelector<HTMLButtonElement>('button')?.focus({preventScroll:true});
  }
  private tick=(time:number)=>{
    if(this.destroyed)return;
    const dt=this.previousTime?Math.min(50,time-this.previousTime):0;this.previousTime=time;
    if(!this.paused){
      this.sceneTime+=dt;
      if(this.animation){this.elapsed+=dt;this.animation.progress=this.settings.lowMotion?1:Math.min(1,this.elapsed/(this.animation.kind==='walk'?160:1000));if(this.animation.progress>=1)this.finishAnimation();}
      else if(this.route.length)this.advance();
      if(this.poseUntil&&time>this.poseUntil){this.pose='idle';this.poseUntil=0;}
      if(this.hintTarget&&time>this.hintUntil)this.hintTarget=undefined;
      if(this.model.state.repaired&&time>this.ambientAt){this.ambientAt=time+5500;this.sound(this.model.id==='cloud-2'?'滴':'叮');}
    }
    this.renderer.draw(this.sceneTime,this.animation,this.pose,this.hintTarget);
    this.frame=requestAnimationFrame(this.tick);
  };
  private resize=()=>{this.renderer.resize();this.syncTiles();this.positionActions();};
  pause(value:boolean){this.paused=value;this.previousTime=0;this.updateUI();}
  configure(settings:SaveData['settings']){this.settings=settings;this.renderer.configure(settings);if(settings.lowMotion&&this.animation)this.finishAnimation();this.updateUI();}
  destroy(){this.destroyed=true;cancelAnimationFrame(this.frame);this.observer.disconnect();this.el.removeEventListener('click',this.click);window.removeEventListener('keydown',this.key);window.removeEventListener('resize',this.resize);}
}
