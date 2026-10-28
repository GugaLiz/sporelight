import { type Level, type WorldNode, totalSpores } from './levels';
export interface RunState { puzzleVersion: 2; spatialVersion?:1; levelId: string; node: string; collected: string[]; activated: string[]; angles: Record<string, number>; vars: Record<string,string>; buddy: string; tune: number; completed: boolean; gridPosition?: {x:number;z:number} }
export interface ActionResult { ok: boolean; message: string; jumped?: boolean; lifted?:boolean }
export interface PuzzleAction { id: string; label: string; selected?: boolean }
const clone = (state: RunState): RunState => JSON.parse(JSON.stringify(state));
export class GameModel {
  state: RunState;
  private history: RunState[] = [];
  constructor(readonly level: Level, saved?: Partial<RunState> | null) {
    this.state = { puzzleVersion:2,spatialVersion:1, levelId:level.id,node:'start',collected:[],activated:[],angles:{},vars:level.lift?{[level.lift.node]:'low'}:{},buddy:level.coop?'follow':level.companion?.[0] ?? 'follow',tune:0,completed:false };
    if (saved?.puzzleVersion === 2 && (!level.gardenRevision||saved.spatialVersion===1) && saved.levelId === level.id && level.nodes.some(n => n.id === saved.node)) {
      this.state.node = saved.node!;
      this.state.collected = [...new Set(Array.isArray(saved.collected) ? saved.collected.filter(id => level.nodes.some(n => n.id === id && n.spore)) : [])];
      this.state.activated = [...new Set(Array.isArray(saved.activated) ? saved.activated.filter(id => level.nodes.some(n => n.id === id && n.mechanism)||(id==='ritual'&&level.sequence?.every(n=>saved.activated!.includes(n)))) : [])];
      for (const n of level.nodes) { const v = saved.vars?.[n.id]; if (typeof v === 'string' && n.targets?.includes(v)) this.state.vars[n.id] = v; }
      if (level.companion?.includes(saved.buddy ?? '')) this.state.buddy = saved.buddy!;
      if(level.coop&&['follow','wait'].includes(saved.buddy??''))this.state.buddy=saved.buddy!;
      if (typeof saved.tune === 'number' && Number.isInteger(saved.tune)) this.state.tune = Math.max(0, Math.min(level.melody?.length ?? 0, saved.tune));
      if (level.melody && this.state.tune === level.melody.length && !this.state.activated.includes('drum')) this.state.activated.push('drum');
      if (level.sequence?.every(id => this.state.activated.includes(id))&&!this.state.activated.includes('ritual')) this.state.activated.push('ritual');
      if (saved.gridPosition && Number.isInteger(saved.gridPosition.x) && Number.isInteger(saved.gridPosition.z)) this.state.gridPosition={x:saved.gridPosition.x,z:saved.gridPosition.z};
      // A valid old name on the far side of a closed co-op gate is not a safe spawn.
      if(level.coop&&this.state.buddy!=='wait'&&!this.state.activated.includes(level.coop.latch)&&!this.pathTo('start')){this.state.node='start';delete this.state.gridPosition;}
    }
  }
  get current(): WorldNode { return this.level.nodes.find(n => n.id === this.state.node)!; }
  get canUndo() { return this.history.length > 0; }
  get stars() { return this.state.collected.length === totalSpores(this.level) ? 3 : this.state.collected.length >= Math.ceil(totalSpores(this.level)/2) ? 2 : 1; }
  get awakened() { return this.level.nodes.filter(n => n.mechanism && this.isActive(n.id)).length; }
  label(id: string) { return this.level.nodes.find(n => n.id === id)?.label ?? id; }
  snapshot() { return clone(this.state); }
  private checkpoint() { this.history.push(this.snapshot()); if (this.history.length > 100) this.history.shift(); }
  undo() { const previous = this.history.pop(); if (!previous) return false; this.state = previous; return true; }
  beamPath() {
    if (!this.level.beam) return [];
    const path = [this.level.beam[0]];
    for (let i=0;i<10;i++) { const target = this.state.vars[path[path.length-1]]; if (!target || path.includes(target)) break; path.push(target); if (target === this.level.beam[1]) break; }
    return path;
  }
  get beamConnected() { return !!this.level.beam && this.beamPath().includes(this.level.beam[1]); }
  isActive(id: string) { return this.state.activated.includes(id) || !!this.state.vars[id] || (this.level.companion?.includes(id) && this.state.buddy === id); }
  isVisible(id: string) {
    if (!this.level.fog || id === 'start' || id === this.state.node || this.state.activated.includes(id)) return true;
    return this.level.edges.some(e => (e.from === id && (e.to === 'start' || this.isActive(e.to))) || (e.to === id && (e.from === 'start' || this.isActive(e.from))));
  }
  edgeOpen(from: string, to: string) {
    const edge = this.level.edges.find(e => (e.from===from && e.to===to)||(e.to===from && e.from===to));
    return !!edge && !edge.jump && this.isVisible(to) && (!edge.gate || this.state.activated.includes(edge.gate)) && (!edge.when || this.state.vars[edge.when[0]]===edge.when[1]) && (!edge.needs || edge.needs.every(id=>this.state.collected.includes(id))) && (!edge.beam || this.beamConnected) && (!edge.companion || this.state.buddy===edge.companion) && (!edge.plate||this.state.buddy==='wait'||!!this.level.coop&&this.state.activated.includes(this.level.coop.latch));
  }
  pathTo(to: string): string[] | null {
    const queue = [[this.state.node]]; const visited = new Set([this.state.node]);
    while(queue.length) { const path=queue.shift()!; const current=path[path.length-1]; if(current===to)return path;
      for(const n of this.level.nodes) if(!visited.has(n.id)&&this.edgeOpen(current,n.id)){visited.add(n.id);queue.push([...path,n.id]);}
    } return null;
  }
  private exitReady(to: string) {
    return to!==this.level.exit || ((!this.level.allSpores || this.state.collected.length===totalSpores(this.level)) && (!this.level.required || this.level.required.every(id=>this.state.collected.includes(id))) && (!this.level.coop||this.state.buddy==='follow'));
  }
  canEnter(to:string,from=this.state.node) { return this.edgeOpen(from,to) && this.exitReady(to); }
  moveWithinGrid(position:{x:number;z:number}) {
    if(this.state.completed)return {ok:false,message:'旅程已经完成。'};
    this.checkpoint();this.state.gridPosition={...position};return {ok:true,message:''};
  }
  private arrive(to: string) {
    this.state.node=to;
    if(this.current.spore&&!this.state.collected.includes(to))this.state.collected.push(to);
    if(to===this.level.exit)this.state.completed=true;
  }
  move(to: string): ActionResult {
    if(this.state.completed || !this.edgeOpen(this.state.node,to))return {ok:false,message:'这段路还没有连通。观察机关与地图上的线索吧。'};
    if(!this.exitReady(to))return {ok:false,message:this.level.coop&&this.state.buddy==='wait'?'小苔灵还在踏板上等你。回去接它，一起走向终点吧。':'花苞还在等你带回关卡需要的微光。'};
    this.checkpoint();this.arrive(to);
    return {ok:true,message:this.state.completed?'这一片苔原，因你而苏醒。':this.current.mechanism?`来到${this.label(to)}，看看下方有哪些选择。`:'这里的微光，已经记住了你的脚步。'};
  }
  actions(): PuzzleAction[] {
    const n=this.current;const active=this.state.activated.includes(n.id);
    if(n.mechanism==='lift')return ['low','high'].map(height=>({id:`choose:${height}`,label:height==='low'?'花阀 ↓ 降回原岸':'花阀 ↑ 升到高庭',selected:this.state.vars[n.id]===height}));
    if(n.mechanism==='latch')return active?[]:[{id:'unlatch',label:'打开永久门闩'}];
    if(n.mechanism==='friend'&&this.level.coop)return [{id:this.state.buddy==='wait'?'call':'wait',label:this.state.buddy==='wait'?'接回小苔灵，一起走':'请小苔灵留在踏板上'}];
    if(n.mechanism==='grow')return [{id:active?'reclaim':'plant',label:active?'回收这粒种子':'在这里播种'}];
    if(['vine','switch','water','reflect'].includes(n.mechanism??''))return (n.targets??[]).map(target=>({id:`choose:${target}`,label:`${n.mechanism==='water'?'引水 → ':n.mechanism==='reflect'?'朝向 → ':n.mechanism==='switch'?'切换 → ':'接桥 → '}${this.label(target)}`,selected:this.state.vars[n.id]===target}));
    if(n.mechanism==='lily')return (n.targets??[]).map(target=>({id:`jump:${target}`,label:`跃向 ${this.label(target)}`}));
    if(n.mechanism==='friend')return [{id:'lure',label:'摇响花铃，呼唤伙伴'}];
    if(n.mechanism==='rhythm')return ['滴','叮','咚'].map(note=>({id:`note:${note}`,label:note}));
    if(n.mechanism==='sequence'||n.mechanism==='light')return [{id:'light',label:n.mechanism==='sequence'?`点亮 ${n.label}`:'点亮苔灯，探索周围'}];
    return [];
  }
  interact(time=0,lowMotion=false): ActionResult {
    const choices=this.actions();
    if(choices.length!==1)return {ok:false,message:choices.length?'这次需要做一个选择，请点击机关面板里的选项。':'这里没有机关。点击另一块石台继续探索。'};
    return this.act(choices[0].id,time,lowMotion);
  }
  act(action: string,time=0,lowMotion=false): ActionResult {
    const n=this.current;
    if(this.state.completed||!this.actions().some(a=>a.id===action))return {ok:false,message:'先走到对应机关旁，再作出选择。'};
    const value=action.split(':')[1];
    if(action==='wait'){this.checkpoint();this.state.buddy='wait';if(!this.state.activated.includes(n.id))this.state.activated.push(n.id);return {ok:true,message:'小苔灵稳稳坐在叶形踏板上。穿过花藤桥，去另一侧打开门闩吧。'};}
    if(action==='unlatch'){this.checkpoint();this.state.activated.push(n.id);return {ok:true,message:'门闩固定好了，道路会一直开着。现在回到踏板旁，亲自接小苔灵。'};}
    if(action==='call'){
      if(!this.state.activated.includes(this.level.coop!.latch))return {ok:false,message:'先到另一侧打开永久门闩，再回来接它，花藤桥才不会收起。'};
      this.checkpoint();this.state.buddy='follow';return {ok:true,message:'你回来啦！小苔灵变成圆滚滚的小蘑菇球，重新跟上你的脚步。'};
    }
    if(action==='plant') {
      if(n.water&&!Object.values(this.state.vars).includes(n.id))return {ok:false,message:'泥土太干了。先用分水花把水引到这里。'};
      if(this.level.seedBudget && this.state.activated.filter(id=>this.level.nodes.find(n=>n.id===id)?.mechanism==='grow').length>=this.level.seedBudget)return {ok:false,message:'只有一粒种子。回到已开花的花床，先回收，再换个地方种。'};
      this.checkpoint();this.state.activated.push(n.id);return {ok:true,message:'花台长出来了。种子可以回收，再为另一处生命带来微光。'};
    }
    if(action==='reclaim'){this.checkpoint();this.state.activated=this.state.activated.filter(id=>id!==n.id);return {ok:true,message:'种子回到菌盖下，花台收起了。现在可以重新播种。'};}
    if(action.startsWith('choose:')) {
      if(n.mechanism==='lift'){
        if(this.state.vars[n.id]===value)return {ok:false,message:'花台已经停在这一层，可以沿接上的道路继续走。'};
        if(this.level.lift?.water&&!Object.values(this.state.vars).includes(this.level.lift.water))return {ok:false,message:'花阀还缺少水。先把分水花引向藤蔓，再乘花台。'};
      }
      this.checkpoint();this.state.vars[n.id]=value;
      return {ok:true,lifted:n.mechanism==='lift',message:n.mechanism==='lift'?(value==='high'?'花台托着你升到了高处。新的落岸接通了。':'花台稳稳回到原岸，小伙伴也一起落下来了。'):n.mechanism==='reflect'?(this.beamConnected?'光源、两片反光叶和水晶连通了！':'叶片已经转向。观察金色光线实际照到了哪里。'):`${this.label(n.id)}现在连接${this.label(value)}。`};
    }
    if(action.startsWith('jump:')) {
      if(n.water&&!Object.values(this.state.vars).includes(n.id))return {ok:false,message:'睡莲还缺少水分。先把分水花引向睡莲。'};
      if(!this.exitReady(value))return {ok:false,message:`先带回${(this.level.required??[]).filter(id=>!this.state.collected.includes(id)).map(id=>this.label(id)).join('、')}，再去终点。`};
      this.checkpoint();if(!this.state.activated.includes(n.id))this.state.activated.push(n.id);this.arrive(value);return {ok:true,jumped:true,message:'睡莲轻轻托起你，落在你选中的地方。'};
    }
    if(action==='lure') {
      const route=this.level.companion??[];const a=route.indexOf(this.state.buddy),b=route.indexOf(n.id);
      if(Math.abs(a-b)!==1||b<0)return {ok:false,message:'伙伴听不见这么远的花铃。先去它身旁相邻的那一站。'};
      this.checkpoint();this.state.buddy=n.id;if(!this.state.activated.includes(n.id))this.state.activated.push(n.id);return {ok:true,message:`伙伴跟着花香来到${this.label(n.id)}，沿金色轨迹继续带它回家吧。`};
    }
    if(action.startsWith('note:')) {
      if(this.state.activated.includes(n.id))return {ok:false,message:'回声已经奏完整了，去雨幕出口吧。'};
      if(!lowMotion&&time%2400>=1200)return {ok:false,message:'水膜正在休息。等蓝色波纹亮起再敲响，已经奏出的音符会保留。'};
      this.checkpoint();
      if(value!==this.level.melody?.[this.state.tune]) {this.state.tune=0;return {ok:true,message:'回声轻轻散开了。再试一次：滴 · 咚 · 叮 · 咚。孢子不会丢失。'};}
      this.state.tune++;if(this.state.tune===this.level.melody.length)this.state.activated.push(n.id);
      return {ok:true,message:this.state.tune===this.level.melody.length?'完整的雨滴之歌打开了雨幕。':`接住了第 ${this.state.tune} 个音符，听听下一声。`};
    }
    if(action==='light') {
      if(this.state.activated.includes(n.id))return {ok:false,message:'这盏灯已经亮了。'};
      if(n.mechanism==='sequence') {
        if(this.state.collected.length<totalSpores(this.level))return {ok:false,message:'先找齐八粒孢子，再重看星图，开始仪式。'};
        const count=this.level.sequence!.filter(id=>this.state.activated.includes(id)).length;
        if(this.level.sequence![count]!==n.id)return {ok:false,message:'这一束光还没轮到。可以重看星图，已经点亮的星座会保留。'};
      }
      this.checkpoint();this.state.activated.push(n.id);
      if(this.level.sequence?.every(id=>this.state.activated.includes(id)))this.state.activated.push('ritual');
      return {ok:true,message:this.level.fog?'苔灯照出了新的小路。也看看两侧，或许藏着微光。':'星座回应了记忆中的光，继续完成仪式吧。'};
    }
    return {ok:false,message:'选择附近的机关试试吧。'};
  }
  status() {
    if(this.level.coop)return `小苔灵：${this.state.buddy==='wait'?'在叶形踏板上等候':'正在跟随'} · 门闩${this.state.activated.includes(this.level.coop.latch)?'已固定':'尚未打开'}${this.level.lift?` · 花台${this.state.vars[this.level.lift.node]==='high'?'在高处':'在低岸'}`:''}`;
    if(this.current.mechanism==='lift')return `花台${this.state.vars[this.current.id]==='high'?'在高处':'在低岸'} · 站在台上也能随时降回去`;
    if(this.level.seedBudget)return `可用种子 ${this.level.seedBudget-this.state.activated.length} / ${this.level.seedBudget} · 花粉 ${this.state.collected.includes('pollen')?'已带回':'未取得'}`;
    if(this.level.beam)return `光路：${this.beamPath().map(id=>this.label(id)).join(' → ')}${this.beamConnected?' · 已连通':' · 未照亮水晶'}`;
    if(this.level.companion)return `伙伴在：${this.label(this.state.buddy)} · 只能呼唤到相邻花铃`;
    if(this.level.melody)return `回声 ${this.state.tune}/${this.level.melody.length} · ${this.level.melody.map((note,i)=>i<this.state.tune?`✓${note}`:note).join(' · ')}`;
    if(this.level.sequence)return `已点亮 ${this.level.sequence.filter(id=>this.state.activated.includes(id)).length}/4 · 点击「重看星图」观察次序`;
    if(this.level.required)return `需要带回：${this.level.required.map(id=>`${this.state.collected.includes(id)?'✓':'○'} ${this.label(id)}`).join(' / ')}`;
    if(this.level.fog)return `已点亮 ${this.state.activated.length}/3 盏苔灯 · 深处的路还藏在雾里`;
    return this.level.kind;
  }
  hint() {
    let id=this.state.node;let message=this.level.subtitle;
    const s=this.state;
    if(this.level.id==='1-2'){id=!s.collected.includes('pollen')?'north':s.activated.includes('north')?'north':'east';message=!s.collected.includes('pollen')?'在北边花床播种，过桥取得花粉。':s.activated.includes('north')?'回到北边花床，回收种子；再去东边播种。':'在东边花床播种，就能带着花粉抵达终点。';}
    if(this.level.id==='1-3'||this.level.id==='3-2'){id=this.level.id==='1-3'?'pivot':'dial';message=`先切换道路取得${this.level.required!.filter(id=>!s.collected.includes(id)).map(id=>this.label(id)).join('、')||'终点通路'}。从支路返回中央机关后，再切换另一条路。`;}
    if(this.level.beam){id='mirrorA';message='第一片叶朝向第二片叶，第二片叶朝向接光水晶。两片叶必须同时保持这个方向。';}
    if(this.level.companion){const i=this.level.companion.indexOf(s.buddy);id=this.level.companion[Math.min(i+1,this.level.companion.length-1)];message=`走到${this.label(id)}，摇响花铃。伙伴只会去相邻一站。`;}
    if(this.level.fog){id=this.level.nodes.find(n=>n.mechanism==='light'&&!s.activated.includes(n.id)&&this.pathTo(n.id))?.id??this.level.exit;message=`点亮${this.label(id)}，看清新的路；侧面的微光可以顺路收集。`;}
    if(this.level.id==='3-3'){id='pump';message=!s.collected.includes('dew')?'先把分水花引到藤蔓，再到干渴藤蔓播种，过桥取露珠。':'回到分水花，把水引向睡莲。到睡莲上选择落点，回望石藏着一粒孢子。';}
    if(this.level.sequence){id=s.collected.length<totalSpores(this.level)?this.level.nodes.find(n=>n.spore&&!s.collected.includes(n.id))!.id:this.level.sequence.find(id=>!s.activated.includes(id))??this.level.exit;message=s.collected.length<totalSpores(this.level)?'先收齐八粒孢子。四条支路都可以去探索。':`下一处是${this.label(id)}。也可以重看星图再记一次。`;}
    if(this.level.id==='2-1'){id=this.state.node==='start'?'start':'upper';message=this.state.node==='start'?'选择「升到高庭」，花台会带着你一起升起。再走到高处睡莲，选择水滴落点。':'从高处睡莲跳往两侧水滴，收齐后再去彼岸。';}
    if(this.level.id==='2-3'&&s.activated.includes('drum')){id='lift';message='回声已经唤醒雨水。走上雨中花台，选择升到高庭，再去出口。';}
    if(this.level.id==='3-1'&&this.isVisible('root')){id=s.activated.includes('lampC')?'end':s.vars.root==='lampC'?'lampC':'root';message=s.activated.includes('lampC')?'最后的苔灯已经亮起，沿照亮的道路去星光出口。':s.vars.root==='lampC'?'沿接通的藤桥走到最后一盏灯，点亮它。':'在雾中转桥台选择接向洞中微光，回来后再接向最后一盏灯。';}
    if(this.level.id==='3-3'&&!s.collected.includes('dew')&&s.activated.includes('vine')){id='lift';message='过藤桥走上水力花台，选择升到高庭，取露珠后原路回台，降回原岸。';}
    if(this.level.id==='3-3'&&s.collected.includes('dew')&&s.vars.lift==='high'){id='lift';message='先回到水力花台，选择降回原岸。再去分水花，把水引向睡莲。';}
    const coop=this.level.coop;
    if(coop&&(!this.level.sequence||s.activated.includes('ritual'))){
      const opened=s.activated.includes(coop.latch);
      id=!opened?(s.buddy==='wait'?coop.latch:coop.pad):s.buddy==='wait'?coop.pad:this.level.exit;
      message=!opened?(s.buddy==='wait'?'伙伴正守住踏板。过桥，在另一侧打开永久门闩。':'走到叶形踏板旁，请小苔灵等一等，帮你打开花藤桥。'):s.buddy==='wait'?'回到叶形踏板旁，亲自接回小苔灵，再一起走向归途。':'门闩已经固定，伙伴也跟上了，一起去终点吧。';
      if(this.level.lift){const lift=this.level.lift.node,high=s.vars[lift]==='high';
        if(opened&&s.buddy==='wait'&&high){id=lift;message='先回到升降睡莲，降回原岸，再走回芦苇踏板，亲自接小苔灵。';}
        else if(s.buddy==='wait'&&!opened&&!high){id=lift;message='伙伴守住了踏板。过花藤桥走上升降睡莲，升到高处，再打开门闩。';}
        else if(opened&&s.buddy==='follow'&&!high){id=lift;message='带着小苔灵一起走上升降睡莲，升到高处，再走向归途。';}
      }
    }
    return {node:id,message};
  }
}
