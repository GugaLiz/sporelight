import { CLOUD_LEVELS, cloudLevel, cloudTiles, type CloudLevelId, type CloudTile, type Landmark } from './data';
export interface CloudState {
  version:1; levelId:CloudLevelId; tile:string; bridge:'north'|'east'; lift:'low'|'high'; seed:boolean;
  latch:boolean; buddy:'sleep'|'follow'|'wait'|'sit'; found:string[]; repaired:boolean;
}
export interface CloudSave { version:1; lastLevel:CloudLevelId; runs:Partial<Record<CloudLevelId,CloudState>>; memories:Partial<Record<CloudLevelId,CloudState>>; completed:CloudLevelId[]; discoveries:Record<string,string[]> }
export const CLOUD_SAVE_KEY='sporelight.cloud-gardens.v1';
export const emptyCloudSave=():CloudSave=>({version:1,lastLevel:'cloud-1',runs:{},memories:{},completed:[],discoveries:{}});
const copy=<T>(v:T):T=>JSON.parse(JSON.stringify(v));
export function normalizeCloudSave(input:unknown):CloudSave {
  const out=emptyCloudSave();if(!input||typeof input!=='object')return out;
  const raw=input as Partial<CloudSave>;
  if(raw.version!==1)return out;
  if(CLOUD_LEVELS.some(l=>l.id===raw.lastLevel))out.lastLevel=raw.lastLevel!;
  out.completed=CLOUD_LEVELS.filter(l=>Array.isArray(raw.completed)&&raw.completed.includes(l.id)).map(l=>l.id);
  for(const level of CLOUD_LEVELS){
    const saved=raw.runs?.[level.id];
    if(saved?.levelId===level.id)out.runs[level.id]=new CloudModel(level.id,saved).snapshot();
    const memory=raw.memories?.[level.id]??saved;
    if(out.completed.includes(level.id)&&memory?.repaired&&memory.levelId===level.id)out.memories[level.id]=new CloudModel(level.id,memory).snapshot();
    const found=raw.discoveries?.[level.id];out.discoveries[level.id]=level.landmarks.filter(l=>l.story&&Array.isArray(found)&&found.includes(l.id)).map(l=>l.id);
  }
  return out;
}
export function loadCloudSave():CloudSave {try{return normalizeCloudSave(JSON.parse(localStorage.getItem(CLOUD_SAVE_KEY)??'null'));}catch{return emptyCloudSave();}}
export function storeCloudSave(save:CloudSave):boolean {try{localStorage.setItem(CLOUD_SAVE_KEY,JSON.stringify(save));return true;}catch{return false;}}
export interface CloudAction { id:string; label:string; landmark:string }
export class CloudModel {
  state:CloudState;
  private history:CloudState[]=[];
  constructor(readonly id:CloudLevelId,saved?:Partial<CloudState>|null){
    this.state={version:1,levelId:id,tile:cloudLevel(id).start,bridge:id==='cloud-3'?'east':'north',lift:'low',seed:false,latch:false,buddy:id==='cloud-1'?'sleep':'follow',found:[],repaired:false};
    if(saved?.version===1&&saved.levelId===id){
      this.state.bridge=saved.bridge==='east'?'east':'north';this.state.lift=saved.lift==='high'?'high':'low';
      for(const key of ['seed','latch','repaired'] as const)this.state[key]=saved[key]===true;
      if(['sleep','follow','wait','sit'].includes(saved.buddy??''))this.state.buddy=saved.buddy!;
      if(id!=='cloud-3'&&this.state.buddy==='wait')this.state.buddy=id==='cloud-1'?'sleep':'follow';
      if(id!=='cloud-1'&&this.state.buddy==='sleep')this.state.buddy='follow';
      this.state.found=cloudLevel(id).landmarks.filter(l=>l.story&&Array.isArray(saved.found)&&saved.found.includes(l.id)).map(l=>l.id);
      if(this.state.repaired){this.state.buddy='sit';if(id==='cloud-1')this.state.seed=true;if(id==='cloud-3')this.state.latch=true;}
      else if(this.state.buddy==='sit')this.state.buddy=id==='cloud-1'?'sleep':'follow';
      if(typeof saved.tile==='string'&&this.tiles.some(t=>t.id===saved.tile))this.state.tile=saved.tile;
      // Corrupt but syntactically valid saves must not strand someone across a closed gate.
      if(id==='cloud-3'&&!this.state.latch&&this.state.buddy!=='wait'&&this.current.x>3){this.state.tile=cloudLevel(id).start;}
      if(!this.state.repaired&&((id!=='cloud-2'&&!this.pathTo(cloudLevel(id).start))||(id==='cloud-2'&&this.current.h===3&&this.state.lift==='low')))this.state.tile=cloudLevel(id).start;
    }
  }
  get level(){return cloudLevel(this.id);}
  get tiles(){return cloudTiles(this.id,this.state.bridge,this.state.lift,this.state.latch||this.state.buddy==='wait');}
  get current(){return this.tiles.find(t=>t.id===this.state.tile)!;}
  snapshot(){return copy(this.state);}
  get canUndo(){return this.history.length>0;}
  private checkpoint(){this.history.push(this.snapshot());if(this.history.length>240)this.history.shift();}
  undo(){const s=this.history.pop();if(!s)return false;this.state=s;return true;}
  neighbors(id:string):CloudTile[]{
    const a=this.tiles.find(t=>t.id===id);if(!a)return [];
    return this.tiles.filter(b=>Math.abs(a.x-b.x)+Math.abs(a.z-b.z)===1&&(a.h===b.h||(Math.abs(a.h-b.h)===1&&(a.kind==='stair'||b.kind==='stair'))));
  }
  pathTo(target:string):string[]|null {
    const queue:[string,string[]][]=[[this.state.tile,[]]],seen=new Set([this.state.tile]);
    for(let i=0;i<queue.length;i++){const [at,path]=queue[i];if(at===target)return path;for(const tile of this.neighbors(at)){if(seen.has(tile.id))continue;seen.add(tile.id);queue.push([tile.id,[...path,tile.id]]);}}
    return null;
  }
  move(id:string){if(this.state.repaired||!this.neighbors(this.state.tile).some(t=>t.id===id))return false;this.checkpoint();this.state.tile=id;return true;}
  landmarkPoint(l:Landmark){return {...l,h:l.id==='valve'?(this.state.lift==='high'?3:0):l.h};}
  near(l:Landmark){const p=this.landmarkPoint(l),c=this.current;return c.h===p.h&&Math.abs(c.x-p.x)+Math.abs(c.z-p.z)<=1;}
  actions():CloudAction[]{
    if(this.state.repaired)return [];
    const actions:CloudAction[]=[];
    for(const l of this.level.landmarks){
      if(!this.near(l))continue;
      if(l.story){if(!this.state.found.includes(l.id))actions.push({id:`discover:${l.id}`,label:l.label,landmark:l.id});continue;}
      if(l.id==='turn'&&this.current.kind!=='bridge')actions.push({id:'rotate',label:this.state.bridge==='north'?'转向右侧庭院 ↻':'转向上方庭院 ↺',landmark:l.id});
      if(l.id==='seed'&&!this.state.seed)actions.push({id:'seed',label:l.label,landmark:l.id});
      if(l.id==='valve'&&this.current.kind==='lift')actions.push({id:'lift',label:this.state.lift==='low'?'让花台升起 ↑':'让花台落下 ↓',landmark:l.id});
      if(l.id==='dock'&&this.current.kind!=='lift'&&this.state.lift==='high')actions.push({id:'lift',label:'把花台唤下来 ↓',landmark:l.id});
      if(l.id==='pad'&&this.state.buddy==='follow')actions.push({id:'wait',label:l.label,landmark:l.id});
      if(l.id==='latch'&&!this.state.latch)actions.push({id:'latch',label:l.label,landmark:l.id});
      if(l.id==='finish')actions.push({id:'repair',label:l.label,landmark:l.id});
    }
    if(this.id==='cloud-2'&&this.current.kind==='lift'&&!actions.some(a=>a.id==='lift'))actions.push({id:'lift',label:this.state.lift==='low'?'让花台升起 ↑':'让花台落下 ↓',landmark:'valve'});
    if(this.id==='cloud-3'&&this.state.buddy==='wait'&&this.near(this.level.landmarks.find(l=>l.id==='pad')!))actions.push({id:'call',label:'接回小苔灵',landmark:'pad'});
    if(this.state.buddy==='follow')actions.push({id:'pet',label:'摸摸小苔灵 ♡',landmark:'buddy'});
    return actions;
  }
  act(id:string):{ok:boolean;message:string}{
    if(!this.actions().some(a=>a.id===id))return {ok:false,message:'走近一点，再和它打个招呼吧。'};
    if(id==='repair'){
      if(this.id==='cloud-1'&&!this.state.seed)return {ok:false,message:'钟塔在等一粒花种。上方的小庭院里，也许藏着它。'};
      if(this.id==='cloud-3'&&this.state.buddy!=='follow')return {ok:false,message:'先打开门闩，再回到叶形踏板旁接上小苔灵。星灯想等你们一起。'};
    }
    if(id==='call'){
      if(!this.state.latch)return {ok:false,message:'先打开拱廊另一侧的门闩，让回家的路一直开着。'};
      const pad=this.level.landmarks.find(l=>l.id==='pad')!;
      if(!this.near(pad))return {ok:false,message:'回到叶形踏板旁，亲自接它一起走吧。'};
    }
    if(id==='pet')return {ok:true,message:'小苔灵蹭了蹭你的手。好啦，我们一起慢慢走。'};
    // Never rotate an occupied span. This guard also protects future controller changes.
    if(id==='rotate'&&this.current.kind==='bridge')return {ok:false,message:'先回到固定观景台，再转动拱桥。'};
    this.checkpoint();
    let message='';
    if(id==='rotate'){this.state.bridge=this.state.bridge==='north'?'east':'north';message=this.state.bridge==='north'?'拱桥接上了上方庭院，沿着亮起的边缘走走看。':'拱桥轻轻转过，右侧庭院的路接通了。';}
    if(id==='lift'){this.state.lift=this.state.lift==='low'?'high':'low';message=this.state.lift==='high'?'花台托着一池雨升起来了。高处的花池就在前面。':'花台回到了岸边，每一滴水都稳稳落下。';}
    if(id==='seed'){this.state.seed=true;message='收好花种。回到观景台，转动拱桥，去钟塔下播种吧。';}
    if(id==='wait'){this.state.buddy='wait';message='小苔灵坐在叶形踏板上，认真地替你守着门。去另一侧打开门闩吧。';}
    if(id==='latch'){this.state.latch=true;message='门闩固定好了。现在回到踏板旁，接上一直等着你的小伙伴。';}
    if(id==='call'){this.state.buddy='follow';message='你回来啦！小苔灵抖抖叶子，重新跟上你的脚步。';}
    if(id.startsWith('discover:')){const l=this.level.landmarks.find(l=>l.id===id.slice(9))!;this.state.found.push(l.id);message=l.story!;}
    if(id==='repair'){this.state.repaired=true;this.state.buddy='sit';message=this.level.restored;}
    return {ok:true,message};
  }
  hint():{target:string;message:string}{
    if(this.state.repaired)return {target:'finish',message:this.level.restored};
    if(this.id==='cloud-1'){
      if(!this.state.seed)return {target:this.state.bridge==='north'?'seed':'turn',message:'上方小庭院里有花种。沿台阶到观景台，让拱桥连接上方。'};
      return {target:this.state.bridge==='east'?'finish':'turn',message:'带着花种回到观景台，把拱桥转向右侧钟塔，再到花床播种。'};
    }
    if(this.id==='cloud-2')return {target:this.current.kind==='lift'?'valve':this.current.h===3?'finish':this.state.lift==='high'?'dock':'valve',message:this.current.h===3&&this.current.kind!=='lift'?'沿高处庭院走到花池，把水引进去。':'走到花台上，再打开花阀。站在花台上也能随时升降。'};
    if(!this.state.latch)return {target:this.state.buddy==='wait'?'latch':'pad',message:this.state.buddy==='wait'?'穿过打开的拱廊，在另一侧打开永久门闩。':'走到叶形踏板旁，请小苔灵等一等，它会帮你打开拱廊。'};
    if(this.state.buddy==='wait')return {target:'pad',message:'回到原来的叶形踏板旁，接回小苔灵。它还在认真等你。'};
    return {target:this.state.bridge==='north'?'finish':'turn',message:'回到内庭的转桥台，让星桥接向上方。带着小苔灵，一起走到屋顶星灯旁。'};
  }
}
