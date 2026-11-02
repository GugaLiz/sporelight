import {gardenLevel} from './levels';
import {cell,modCell,DIRECTION,type Actor,type Tile,type Point,type GardenState,type GardenLevel,type Command,type Landmark} from './types';
const clone=<T>(v:T):T=>JSON.parse(JSON.stringify(v));
export const same=(a:Point,b:Point)=>a.x===b.x&&a.z===b.z&&a.h===b.h;
export class GardenWorld {
 readonly level:GardenLevel;state:GardenState;private history:GardenState[]=[];
 constructor(id:string,saved?:Partial<GardenState>|null){
  this.level=gardenLevel(id);const l=this.level;
  this.state={designVersion:2,levelId:l.id,active:'luvie',actors:{luvie:l.start,buddy:l.buddy??l.start},follow:!['1-4','2-3','3-1','3-4'].includes(l.id),growth:Object.fromEntries(l.roots.map(r=>[r.id,[]])),turns:Object.fromEntries(l.modules.map(m=>[m.id,0])),flags:[],items:{},collected:[],observations:[],discovered:[],water:0,mode:0,frozen:null,song:['turn','rise','rest'],beat:0,playing:false,completed:false};
  if(l.id==='1-4')this.state.items.bell={tile:cell(-2,5),angle:0};
  if(l.id==='2-2'){this.state.items.mirrorA={tile:cell(1,1),angle:0};this.state.items.mirrorB={tile:cell(4,3),angle:0};}
  if(l.id==='2-1')this.state.items.dew={tile:cell(0,4),angle:0};
  if(l.id==='2-4')this.state.items.bug={tile:cell(-4,0),angle:0};
  if(l.id==='3-1')this.state.items.lamp={tile:cell(-3,0),angle:0};
  if(l.id==='3-2'){this.state.items.sunPost={tile:cell(-2,0),angle:0};this.state.items.moonPost={tile:cell(-2,1),angle:0};}
  if(l.id==='3-3')this.state.items.dew={tile:cell(8,0),angle:0};
  if(l.id==='3-4')this.state.items.mirror={tile:cell(1,-4),angle:0};
  if(saved?.designVersion===2&&saved.levelId===id){
   const initial=clone(this.state);
   try{
    const s=clone(saved) as GardenState;
    if(!s.actors||!['luvie','buddy'].includes(s.active)||!Array.isArray(s.flags)||!Array.isArray(s.collected)||!Array.isArray(s.observations)||!s.items||!s.turns||!s.growth)throw Error('shape');
    if(s.flags.some(v=>typeof v!=='string')||s.collected.some(v=>typeof v!=='string')||s.observations.some(v=>typeof v!=='string'))throw Error('lists');
    s.follow=s.follow===true;s.playing=s.playing===true;s.completed=s.completed===true;s.discovered=Array.isArray(s.discovered)?s.discovered.filter(id=>typeof id==='string'):[];
    if(s.shadowMemory&&(!Array.isArray(s.shadowMemory)||s.shadowMemory.length!==2||s.shadowMemory.some(p=>!Number.isInteger(p.x)||!Number.isInteger(p.z)||p.h!==0)))throw Error('shadow');
    const validCollections=new Set(l.id==='3-4'?['root','rain','star','moon'].flatMap(f=>[0,1].map(n=>`gift-${f}-${n}`)):l.collectibles.map(c=>c.id));s.collected=[...new Set(s.collected.filter(id=>validCollections.has(id)))];
    s.water=[0,1,2].includes(s.water)?s.water:0;s.mode=s.mode===1?1:0;s.frozen=s.frozen===0||s.frozen===1?s.frozen:null;
    s.beat=Math.max(0,Math.min(3,Number.isInteger(s.beat)?s.beat:0));s.song=Array.isArray(s.song)&&s.song.length===3&&new Set(s.song).size===3&&s.song.every(t=>['turn','rise','rest'].includes(t))?s.song:['turn','rise','rest'];
    for(const m of l.modules){const n=s.turns[m.id];s.turns[m.id]=Number.isInteger(n)?((n%4)+4)%4:0;}
    for(const root of l.roots)if(!Array.isArray(s.growth[root.id])||s.growth[root.id].length>root.budget||new Set(s.growth[root.id]).size!==s.growth[root.id].length)throw Error('root');
    if(s.trial){const t=JSON.parse(s.trial);if(t.designVersion!==2||t.trial||t.levelId!==id)throw Error('trial');}
    for(const [key,item]of Object.entries(s.items)){if(!initial.items[key]||!item||typeof item.tile!=='string'||!Number.isInteger(item.angle)||item.holder&&!['luvie','buddy'].includes(item.holder)||item.holder&&item.tile||key.startsWith('mirror')&&item.holder==='buddy')throw Error('item');}
    if(Object.keys(initial.items).some(k=>!s.items[k]))throw Error('missing item');
    for(const [key,item]of Object.entries(s.items))if(key==='dew'&&(item.picked===true||item.holder||item.tile!==initial.items[key].tile))item.picked=true;else delete item.picked;
    if(Object.values(s.items).filter(i=>i.holder==='luvie').length>1||Object.values(s.items).filter(i=>i.holder==='buddy').length>1)throw Error('hands');
    this.state=s;
    const tiles=this.tiles;
    for(const a of ['luvie','buddy'] as Actor[])if(!tiles.some(t=>t.id===s.actors[a]&&!t.solid&&(a==='buddy'||!t.small)))throw Error('position');
    for(const item of Object.values(s.items))if(item.tile&&!tiles.some(t=>t.id===item.tile))throw Error('item tile');
    for(const r of l.roots){let p=this.pointFor(r.at);for(const id of s.growth[r.id]){const t=this.growthPoint(id,r.h);if(!t||Math.abs(t.x-p.x)+Math.abs(t.z-p.z)!==1||!r.sockets.some(([x,z])=>x===t.x&&z===t.z))throw Error('root path');p=t;}}
   }catch{this.state=initial;}
  }
 }
 snapshot(){return clone(this.state);}
 get canUndo(){return this.history.length>0;}
 private checkpoint(){this.history.push(this.snapshot());if(this.history.length>400)this.history.shift();}
 undo(){const last=this.history.pop();if(!last)return false;this.state=last;return true;}
 flag(f:string){return this.state.flags.includes(f);}
 private set(f:string){if(!this.flag(f))this.state.flags.push(f);}
 get actor(){return this.state.active;}
 pointFor(id:string):Tile {const p=this.tiles.find(t=>t.id===id);if(!p)throw Error(`Unknown tile ${id}`);return p;}
 get point(){return this.pointFor(this.state.actors[this.actor]);}
 get budget(){const r=this.level.roots[0];return r?r.budget-(this.state.growth[r.id]?.length??0):0;}
 connected(root=this.level.roots[0]){if(!root)return false;const path=this.state.growth[root.id],p=path?.length?this.growthPoint(path[path.length-1],root.h):undefined;return !!p&&p.x===root.goal[0]&&p.z===root.goal[1];}
 growthGuidance(){
  const root=this.level.roots[0];if(!root||this.connected(root))return undefined;
  const grown=this.state.growth[root.id],origin=this.pointFor(root.at),end=grown.length?this.growthPoint(grown[grown.length-1],root.h)!:origin;
  const used=new Set(grown),queue:{point:Point;route:Point[]}[]=[{point:end,route:[]}];
  for(let i=0;i<queue.length;i++){const current=queue[i];if(current.point.x===root.goal[0]&&current.point.z===root.goal[1])return {root,origin,end,route:current.route,retract:false};
   if(grown.length+current.route.length>=root.budget)continue;
   for(const [dx,dz]of Object.values(DIRECTION)){const x=current.point.x+dx,z=current.point.z+dz,id=`g:${root.id}:${x}:${z}`;if(!root.sockets.some(p=>p[0]===x&&p[1]===z)||used.has(id)||current.route.some(p=>p.x===x&&p.z===z))continue;const point={x,z,h:root.h};queue.push({point,route:[...current.route,point]});}
  }
  return {root,origin,end,route:[] as Point[],retract:true};
 }
 private growthPoint(id:string,h:number):Tile|undefined{const parts=/^g:([^:]+):(-?\d+):(-?\d+)$/.exec(id);return parts?{id,x:Number(parts[2]),z:Number(parts[3]),h,kind:'root'}:undefined;}
 modulePoint(id:string,local:[number,number]):Point {
  const m=this.level.modules.find(m=>m.id===id)!;let [x,z]=local;const turn=this.state.turns[id]??0;
  if(m.kind==='rotate')for(let i=0;i<turn;i++)[x,z]=[-z,x];
  const shift=m.kind==='slide'?(turn%2)*(m.distance??0):0;
  let h=m.h;if(m.kind==='lift')h=id==='float'?this.state.water:turn%2?m.high??2:m.low??0;
  if(this.level.id==='2-3'&&id==='stage')h=this.flag('raised')?2:0;
  return {x:m.x+x+(m.axis==='x'?shift:0),z:m.z+z+(m.axis==='z'?shift:0),h};
 }
 get tiles():Tile[]{
  const s=this.state,l=this.level;let base=l.tiles.map(t=>({...t}));
  if(l.sanctuary){base.push(...l.sanctuary.tiles.map(t=>({...t,solid:t.x===l.sanctuary!.fountain.x&&t.z===l.sanctuary!.fountain.z})));base.push({...l.sanctuary.gate,solid:!this.flag('home')});}
  const add=(x:number,z:number,h=0,kind:Tile['kind']='root',small=false,id=cell(x,z))=>base.push({id,x,z,h,kind,small});
  const line=(a:[number,number],b:[number,number],h=0,small=false)=>{let [x,z]=a;while(x!==b[0]||z!==b[1]){if(x!==b[0])x+=Math.sign(b[0]-x);else z+=Math.sign(b[1]-z);add(x,z,h,'root',small);}};
  if(l.id==='1-1')base=base.filter(t=>t.z!==1);
  if(l.id==='1-4'){
   const handle=l.tiles.find(t=>t.id===l.marks.find(m=>m.id==='hold')?.tile),holder=base.find(t=>t.id===s.actors.luvie);
   const holding=this.flag('hold')&&handle&&holder&&holder.h===handle.h&&Math.abs(holder.x-handle.x)+Math.abs(holder.z-handle.z)<=1;
   if(this.flag('latch')||holding)line([-2,0],[2,0]);
   if(this.flag('latch')||s.actors.buddy===cell(3,5))line([-3,1],[-3,4]);
  }
  if(l.id==='2-1'){
   if(s.water!==0)base=base.filter(t=>t.z<2);
   if(s.water===0)add(-2,0);
   if(s.water===1&&this.flag('care'))add(2,0,1);
   if(s.water===2)add(0,-2,2);
  }
  if(l.id==='2-2'&&!this.beamHits(4,0)){base=base.filter(t=>!(t.z===0&&t.x>=3));}
  if(l.id==='2-3'&&this.flag('latch')){for(let z=-1;z>=-4;z--)add(-4,z,Math.round((-z-1)*2/3));line([-4,-4],[0,-4],2);}
  if(l.id==='2-4'){if((s.turns.boat??0)%2===0)add(-2,0);else add(8,0);if(!this.flag('pollinated'))base=base.filter(t=>t.x<9);}
  if(l.id==='3-1'&&(this.flag('window')||this.lampAtReceiver()))line([-2,0],[2,0]);
  if(l.id==='3-2'){
   for(const mode of [0,1] as const)if(s.mode===mode||s.frozen===mode){const points=s.frozen===mode&&s.shadowMemory?s.shadowMemory:this.projection(mode);points.forEach((p,i)=>add(p.x,p.z,p.h,'shadow',false,mode===0?(i===0?'shadow:sun':'shadow:sun:2'):`shadow:moon:${i+1}`));}
  }
  if(l.id==='3-3'||l.id==='3-4'){
   if(this.connected()||this.flag('root')){
    if(l.id==='3-3')add(4,-2);else{add(4,-3);add(4,-2);}
   }
   if((s.turns.lift??0)%2)add(6,0,2);
   if(l.id==='3-3'&&this.flag('root')&&(s.turns.water??0)===1&&(s.turns.lift??0)%2){line([4,1],[4,2],2);line([4,2],[0,2],2);add(0,3,2,'shadow');}
   if(l.id==='3-4'){
    if(this.flag('root')){line([0,-4],[-4,-4]);for(let z=-3;z<=0;z++)add(-4,z);}
    add(8,2,2);if(this.flag('star'))line([8,2],[8,3],2);
   }
  }
  // Modules use stable local identities, even as their world coordinates change.
  for(const m of l.modules)for(const local of m.shape){if(l.id==='3-3'&&m.id==='lift'&&local[0]===-1&&local[1]===0&&!this.flag('root'))continue;base.push({id:modCell(m.id,...local),...this.modulePoint(m.id,local),kind:'module',module:m.id,local,small:m.small});}
  for(const r of l.roots)for(const id of s.growth[r.id]??[]){const p=this.growthPoint(id,r.h);if(p)base.push(p);}
  const coords=new Map<string,Tile>();
  for(const t of base){const key=`${t.x},${t.z},${t.h}`;const old=coords.get(key);if(!old||Object.values(s.actors).includes(t.id)||Object.values(s.items).some(i=>i.tile===t.id))coords.set(key,t);}
  return [...coords.values()];
 }
 /** Light traces actual grid positions and mirror normals; it does not select a target ID. */
 rays():Point[]{
  if(!['2-2','3-4'].includes(this.level.id))return [];
  let x=this.level.id==='2-2'?0:8,z=this.level.id==='2-2'?1:4,dx=this.level.id==='2-2'?1:0,dz=this.level.id==='2-2'?0:-1,h=this.level.id==='2-2'?0:2;
  if(this.level.id==='3-4'&&(this.state.turns.light??0)!==1)return [{x,z,h}];
  const points:Point[]=[{x,z,h}],seen=new Set<string>();
  for(let n=0;n<48;n++){
   x+=dx;z+=dz;const key=`${x},${z},${dx},${dz}`;if(seen.has(key))break;seen.add(key);points.push({x,z,h});
   if(this.level.id==='2-2'&&x===4&&z===0||this.level.id==='3-4'&&x===-4&&z===0)break;
   if(this.level.walls?.some(p=>p[0]===x&&p[1]===z))break;
   for(const [name,item]of Object.entries(this.state.items))if(name.startsWith('mirror')&&!item.holder&&item.tile){const p=this.rawItemPoint(item.tile);if(p&&p.x===x&&p.z===z&&p.h===h){[dx,dz]=item.angle%2?[-dz,-dx]:[dz,dx];break;}}
   if(x< -6||x>15||z< -7||z>12)break;
  }return points;
 }
 private rawItemPoint(id:string):Point|undefined{
  const m=/^m:([^:]+):(-?\d+):(-?\d+)$/.exec(id);if(m)return this.modulePoint(m[1],[Number(m[2]),Number(m[3])]);
  const f=/^f:(-?\d+):(-?\d+)$/.exec(id);return f?this.level.tiles.find(t=>t.id===id)??{x:+f[1],z:+f[2],h:0}:undefined;
 }
 beamHits(x:number,z:number){return this.rays().some(p=>p.x===x&&p.z===z);}
 projection(mode:0|1):Point[]{const item=this.state.items[mode===0?'sunPost':'moonPost'];if(!item||item.holder||!item.tile)return [];const p=this.rawItemPoint(item.tile);if(!p)return [];return mode===0?[{x:p.x+1,z:p.z,h:0},{x:p.x+2,z:p.z,h:0}]:[{x:p.x-1,z:p.z+2,h:0},{x:p.x-1,z:p.z+3,h:0}];}
 lampRay():Point[]{const lamp=this.state.items.lamp;if(!lamp)return [];const p=this.rawItemPoint(lamp.holder?this.state.actors[lamp.holder]:lamp.tile);if(!p)return [];const [dx,dz]=Object.values(DIRECTION)[lamp.angle%4],out:Point[]=[p];for(let i=1;i<=8;i++){const point={x:p.x+dx*i,z:p.z+dz*i,h:p.h};out.push(point);if(!this.flag('window')&&point.x===3&&point.z===2)break;}return out;}
 lampAtReceiver(){return this.lampRay().some(p=>p.x===3&&p.z===3);}
 visible(tile:Tile){if(this.level.id!=='3-1'||this.flag('window')||this.state.discovered?.includes(tile.id))return true;const positions=Object.values(this.state.actors).map(id=>this.tiles.find(t=>t.id===id)).filter(Boolean) as Tile[];return positions.some(p=>Math.abs(p.x-tile.x)+Math.abs(p.z-tile.z)<=2)||this.lampRay().some(p=>Math.abs(p.x-tile.x)+Math.abs(p.z-tile.z)<=1);}
 neighbors(id:string,actor=this.actor,tiles=this.tiles){const p=tiles.find(t=>t.id===id);if(!p)return [];return tiles.filter(t=>!t.solid&&!(actor==='luvie'&&t.small)&&Math.abs(p.x-t.x)+Math.abs(p.z-t.z)===1&&Math.abs(p.h-t.h)<=1);}
 pathTo(id:string,actor=this.actor):string[]|null{
  const tiles=this.tiles,queue:[string,string[]][]=[[this.state.actors[actor],[]]],seen=new Set([this.state.actors[actor]]);
  for(let i=0;i<queue.length;i++){const [p,path]=queue[i];if(p===id)return path;for(const t of this.neighbors(p,actor,tiles))if(!seen.has(t.id)){seen.add(t.id);queue.push([t.id,[...path,t.id]]);}}
  return null;
 }
 near(tile:string,actor=this.actor){const tiles=this.tiles,p=tiles.find(t=>t.id===this.state.actors[actor]),q=tiles.find(t=>t.id===tile);return !!p&&!!q&&Math.abs(p.h-q.h)<=.1&&Math.abs(p.x-q.x)+Math.abs(p.z-q.z)<=1;}
 get together(){const a=this.pointFor(this.state.actors.luvie),b=this.pointFor(this.state.actors.buddy);return Math.abs(a.x-b.x)+Math.abs(a.z-b.z)<=1&&a.h===b.h;}
 move(id:string){
  if(this.state.playing||!this.neighbors(this.state.actors[this.actor]).some(t=>t.id===id))return {ok:false,message:'这里尚未接通，看看地面、高度与庭院的朝向。'};
  return this.transaction(()=>{
   this.state.actors[this.actor]=id;
   if(this.actor==='luvie')this.state.flags=this.state.flags.filter(f=>f!=='hold');
   if(this.state.follow){const other:Actor=this.actor==='luvie'?'buddy':'luvie';const p=this.pathTo(id,other);if(p?.length)this.state.actors[other]=p[0];}
   return '石板记住了两双小脚印。';
  });
 }
 private transaction(change:()=>string){
  const before=this.snapshot();let message:string;
  try{message=change();const tiles=this.tiles;
   for(const a of ['luvie','buddy'] as Actor[])if(!tiles.some(t=>t.id===this.state.actors[a]&&!t.solid&&!(a==='luvie'&&t.small)))throw Error('这次变化会收走脚下的路，先把两位旅人带到安全台。');
   for(const item of Object.values(this.state.items))if(item.tile&&!item.holder&&!tiles.some(t=>t.id===item.tile))throw Error('先把关键物件放到安全台，再改变这段路。');
   this.updateOutcomes();this.collect();
  }catch(e){this.state=before;return {ok:false,message:e instanceof Error?e.message:'先回安全台，再试一种办法。'};}
  this.state=clone(this.state);this.history.push(before);if(this.history.length>400)this.history.shift();return {ok:true,message};
 }
 private collect(){for(const c of this.level.collectibles)if(!this.state.collected.includes(c.id)&&Object.values(this.state.actors).includes(c.tile))this.state.collected.push(c.id);if(this.level.id==='3-1'){const seen=this.tiles.filter(t=>this.visible(t)).map(t=>t.id);this.state.discovered=[...new Set([...(this.state.discovered??[]),...seen])];}}
 private updateOutcomes(){
  if(this.level.id==='3-4'){
   if(this.connected())this.set('root');
   if(this.flag('root')&&this.state.turns.water===1)this.set('rain');
   if(this.flag('rain')&&this.state.items.mirror?.tile===cell(8,0)&&this.beamHits(-4,0))this.set('star');
   if(this.flag('star')&&this.together&&this.near(cell(-4,0),'luvie'))this.set('moon');
   for(const flag of ['root','rain','star','moon'])if(this.flag(flag))for(let i=0;i<2;i++){const id=`gift-${flag}-${i}`;if(!this.state.collected.includes(id))this.state.collected.push(id);}
  }
 }
 ready(){
  const s=this.state;switch(this.level.id){
   case '1-1':case '1-2':return this.connected();
   case '1-3':return true;
   case '1-4':return this.flag('latch')&&this.flag('home')&&this.together;
   case '2-1':return this.flag('care')&&s.water===1;
   case '2-2':return this.beamHits(4,0);
   case '2-3':return this.flag('latch')&&this.together;
   case '2-4':return this.flag('pollinated');
   case '3-1':return this.flag('window')&&this.together&&!!s.items.lamp.holder;
   case '3-2':return (s.mode===0||s.frozen===0)&&(s.mode===1||s.frozen===1);
   case '3-3':return this.flag('root')&&s.turns.water===1&&s.turns.lift%2===1;
   case '3-4':return ['root','rain','star','moon'].every(f=>this.flag(f))&&s.turns.inner===1&&s.turns.water===1&&this.beamHits(-4,0)&&this.together;
  }return false;
 }
 commands():Command[]{
  if(this.state.completed)return [...(this.level.dual?[{id:'switch',label:'换手看看花园'},{id:'follow',label:this.state.follow?'关闭自动同行':'沿小路一起走',selected:this.state.follow}]:[]),...this.level.marks.filter(m=>(m.kind==='rest'||m.kind==='observe')&&this.near(m.tile)).map(m=>({id:`observe:${m.id}`,label:m.label}))];
  const out:Command[]=[];const s=this.state;
  if(s.active==='luvie'&&s.follow&&!this.together&&this.level.marks.some(m=>m.kind==='core'&&this.near(m.tile))&&this.pathTo(s.actors.luvie,'buddy')?.length)out.push({id:'rejoin',label:'等伙伴沿路跟上'});
  if(this.level.dual)out.push({id:'switch',label:this.actor==='luvie'?'换手：操控小苔灵':'换手：操控露薇'});
  if(this.level.dual)out.push({id:'follow',label:s.follow?'各自等候':'一起走（需要连通）',selected:s.follow});
  for(const root of this.level.roots)if(this.near(root.at)&&this.actor==='luvie'){
   const path=s.growth[root.id],end=path.length?this.growthPoint(path[path.length-1],root.h)!:this.pointFor(root.at);
   for(const [dir,[dx,dz]]of Object.entries(DIRECTION)){const x=end.x+dx,z=end.z+dz;if(path.length<root.budget&&root.sockets.some(p=>p[0]===x&&p[1]===z)&&!path.includes(`g:${root.id}:${x}:${z}`))out.push({id:`grow:${root.id}:${dir}`,label:`引芽 ${({up:'↑',right:'→',down:'↓',left:'←'} as Record<string,string>)[dir]} · 余${this.budget}`,target:`g:${root.id}:${x}:${z}`});}
   if(path.length&&!this.flag('root'))out.push({id:`retract:${root.id}`,label:'收回最后一节芽'});
  }
  for(const m of this.level.marks)if(this.near(m.tile)){
   const own=this.level.modules.find(mod=>modCell(mod.id)===m.tile);
   if(m.kind==='turn'&&own){out.push({id:`turn:${own.id}`,label:own.kind==='slide'?'移动整座花园 ⇄':'连人带庭院转90° ↻'});}
   if(m.kind==='valve')out.push({id:`valve:${m.id}`,label:m.id==='mode'?'切换日／月':this.level.id==='2-1'?`水位：${['低','中','高'][s.water]} → ${['低','中','高'][(s.water+1)%3]}`:own?.kind==='rotate'?'转动沟槽与庭院 ↻':s.turns.lift%2?'花阀：安全下降 ↓':'花阀：上升 ↑'});
   if(m.kind==='lever'&&this.actor==='luvie')out.push({id:`use:${m.id}`,label:m.id==='hold'&&this.flag('hold')?'保持拉杆 · 换小苔灵过桥':this.flag(m.id)?'已经安定了':m.label});
   if(m.kind==='latch'&&this.actor==='luvie'&&!this.flag('latch'))out.push({id:'use:latch',label:m.label});
   if(m.kind==='flower'&&['care','home','plant','invite'].includes(m.id)&&!(m.id==='home'&&this.flag('home')))out.push({id:`use:${m.id}`,label:m.label});
   if(m.id==='freeze')out.push({id:'freeze',label:'留影苔：固定当前投影'});
   if(m.kind==='core'&&this.actor==='luvie')out.push({id:'repair',label:'一起种下微光 ✧'});
   if(m.kind==='rest'||m.kind==='observe')out.push({id:`observe:${m.id}`,label:m.label});
   if(m.kind==='song'){
    for(let i=0;i<2;i++)out.push({id:`swap:${i}`,label:`交换第${i+1}、${i+2}片动作叶`});
    out.push({id:'play',label:s.playing?'暂停试奏':'开始／继续试奏'}, {id:'beat',label:'单步试奏下一拍'},{id:'resetSong',label:'重新排练（恢复试奏前）'});
   }
  }
  for(const [id,item]of Object.entries(s.items)){
   if(item.holder===this.actor){
    const slot=this.level.marks.find(m=>m.kind==='slot'&&this.near(m.tile));
    out.push({id:`drop:${id}:${slot?.tile??s.actors[this.actor]}`,label:slot?`放到${slot.label}`:'放在脚边的固定地面'});
    if(id.startsWith('mirror')||id==='lamp')out.push({id:`angle:${id}`,label:id==='lamp'?'把灯转90°':'转动手中的反光叶'});
   }else if(!item.holder&&item.tile&&this.near(item.tile)&&id!=='bug'){
    if(id!=='mirrorA'&&(this.actor==='luvie'||id==='lamp'))out.push({id:`take:${id}`,label:`${id==='lamp'?'提起暖灯':id.endsWith('Post')?'搬起日月影柱':id.startsWith('mirror')?'搬起反光叶':id==='dew'?'接住露珠':'收好门铃'}`});
    if(id.startsWith('mirror'))out.push({id:`angle:${id}`,label:'转动反光叶朝向'});
   }
  }
  return [...new Map(out.map(c=>[c.id,c])).values()];
 }
 act(id:string,internal=false):{ok:boolean;message:string}{
  if(this.state.completed&&id!=='switch'&&id!=='follow'&&!id.startsWith('observe:'))return {ok:false,message:'花园已经安定了，留下看看吧。'};
  if(!internal&&!this.commands().some(c=>c.id===id))return {ok:false,message:'走近操作点，或换一位旅人试试。'};
  const s=this.state,l=this.level;
  return this.transaction(()=>{
   if(id==='switch'){s.active=this.actor==='luvie'?'buddy':'luvie';s.follow=false;return '换你来帮我啦。另一位会留在原地安心等候。';}
   if(id==='rejoin'){const path=this.pathTo(s.actors.luvie,'buddy');if(!path?.length)throw Error('伙伴身旁的路还没有接通，先换手看看。');s.actors.buddy=path[0];return '小苔灵沿石板靠近你，一起把微光种下。';}
   if(id==='follow'){if(!s.follow&&!this.pathTo(s.actors[this.actor],this.actor==='luvie'?'buddy':'luvie'))throw Error('两位之间还没有路，先接上归途。');s.follow=!s.follow;return s.follow?'一起慢慢走。':'各自站好，再安排一次配合。';}
   if(id.startsWith('grow:')){const [,root,dir]=id.split(':'),r=l.roots.find(r=>r.id===root)!,path=s.growth[root],p=path.length?this.growthPoint(path[path.length-1],r.h)!:this.pointFor(r.at);if(l.id==='3-3'&&![0,3].includes(s.turns.water)&&!this.flag('root'))throw Error('藤根还没接到水，先把沟槽转向北侧。');const [dx,dz]=DIRECTION[dir as keyof typeof DIRECTION];path.push(`g:${root}:${p.x+dx}:${p.z+dz}`);return '根须托起一节石板，你安排的小路正在生长。';}
   if(id.startsWith('retract:')){s.growth[id.split(':')[1]].pop();return '叶片合拢休息，可以重新安排方向。';}
   if(id.startsWith('turn:')){const m=id.split(':')[1];s.turns[m]=(s.turns[m]+1)%(l.modules.find(a=>a.id===m)?.kind==='slide'?2:4);return '整座庭院托着旅人转向远方。看看出口、水与光的位置。';}
   if(id.startsWith('valve:')){
    const key=id.split(':')[1];if(key==='mode')s.mode=s.mode===0?1:0;
    else if(l.id==='2-1')s.water=(s.water+1)%3;
    else if(key==='water')s.turns.water=(s.turns.water+1)%4;
    else{if(s.turns.lift%2===0&&l.id==='3-3'&&![0,1].includes(s.turns.water))throw Error('花台没有上升动力，但随时可以安全下降。');if(l.id==='3-4'&&s.turns.lift%2===0&&!this.flag('rain'))throw Error('请小苔灵去送水庭，把水接向花台。');s.turns.lift=(s.turns.lift+1)%2;}
    return '水位与落岸变化了，脚下的旅人和物件也一起移动。';
   }
   if(id==='freeze'){const points=this.projection(s.mode);if(!points.length)throw Error('先把当前光照对应的影柱放到槽中，再留影。');s.frozen=s.mode;s.shadowMemory=points;return '留影苔记住了这段实际投影，再换一个时刻看看。';}
   if(id.startsWith('take:')){const item=s.items[id.slice(5)];if(Object.values(s.items).some(i=>i.holder===this.actor))throw Error('一次带一件，先把随身的物品放好。');item.holder=this.actor;item.tile='';if(id==='take:dew'){item.picked=true;return '用柔软的叶片包好清露，收进贴身的小挎袋。';}return id==='take:bell'?'把门铃收进小挎袋，带回鼹鼠的家。':'稳稳带好了，沿接通的路继续走吧。';}
   if(id.startsWith('drop:')){const [,name,...parts]=id.split(':'),item=s.items[name],tile=parts.join(':');if(this.pointFor(tile).kind==='root')throw Error('先把关键物件放到固定台或庭院上的放置槽。');item.tile=tile;delete item.holder;return '稳稳放好了，看看光与道路有没有一起改变。';}
   if(id.startsWith('angle:')){const item=s.items[id.slice(6)];item.angle=(item.angle+1)%(id.slice(6)==='lamp'?4:2);return '叶片转向了，光沿实际方向前进。';}
   if(id==='use:hold'){this.set('hold');return '露薇扳住重杆。换小苔灵走过短桥与低拱吧。';}
   if(id==='use:latch'){this.set('latch');return '归途固定了，两位可以沿真实的路重新会合。';}
   if(id==='use:window'){if(!this.lampAtReceiver())throw Error('先让小苔灵把灯带到照孔，朝上照亮接收叶。');this.set('window');return '石窗打开，灯井学会自己发光了。现在把伙伴与暖灯接回来。';}
   if(id==='use:home'){const item=s.items.bell;if(item.holder!=='luvie')throw Error('门铃还在内庭，带回来给鼹鼠吧。');delete item.holder;item.tile='';this.set('home');return '门铃响了，花门打开了！接上小苔灵，沿花径去小花园中央种下微光吧。';}
   if(id==='use:care'){const item=s.items.dew;if(item.holder!==this.actor)throw Error('先带回一滴清露，再把它留给花心。');delete item.holder;item.tile='';this.set(l.id==='3-3'?'root':'care');return '被照顾的根系学会蓄水，留下了一条安定的路。';}
   if(id==='use:plant'){this.set('plant');return '蜜花展开了，光虫有了安心停脚的地方。';}
   if(id==='use:invite'){if(!this.flag('plant'))throw Error('先种一朵蜜花，再邀请光虫。');const bug=s.items.bug;if(!s.turns.boat){if(bug.tile===cell(-4,0))bug.tile=modCell('boat');else throw Error('光虫已经在花园里，载它去另一岸吧。');}else{if(bug.tile!==modCell('boat'))throw Error('还没有接上光虫，先把花园移回花粉岸。');bug.tile=cell(10,0);this.set('pollinated');}return '小花园载着光虫，把花粉送到了新的家。';}
   if(id.startsWith('observe:')){const key=id.slice(8);if(!s.observations.includes(key))s.observations.push(key);return l.marks.find(m=>m.id===key)?.text??l.story;}
   if(id.startsWith('swap:')){if(s.beat||s.playing)throw Error('先重新排练，再换动作叶的位置。');const n=+id.slice(5);[s.song[n],s.song[n+1]]=[s.song[n+1],s.song[n]];return '叶片换好位置了，试试顺序会带来什么不同。';}
   if(id==='resetSong'){if(s.trial){const trial=JSON.parse(s.trial) as GardenState;const collections=[...s.collected],observations=[...s.observations];this.state=trial;this.state.collected=[...new Set([...trial.collected,...collections])];this.state.observations=observations;this.state.playing=false;this.state.beat=0;delete this.state.trial;}return '回到试奏前，两位和庭院都稳稳站好了。';}
   if(id==='play'||id==='beat'){
    if(!s.trial){const trial=clone(s);delete trial.trial;s.trial=JSON.stringify(trial);}
    if(id==='play'){s.playing=!s.playing;return s.playing?'雨歌开始，一拍一拍看花园怎样变化。':'暂停试奏，慢慢看看下一片叶。';}
    if(s.beat>=3){s.playing=false;return '短句已经演奏完了，可以到岸边固定便道，或重新排练。';}
    const note=s.song[s.beat++];if(note==='turn'){if(!this.flag('raised'))s.turns.stage=(s.turns.stage+1)%4;}if(note==='rise')this.set('raised');if(s.beat>=3)s.playing=false;
    return note==='turn'&&this.flag('raised')?'高处限位挡住了转轴。可以重新排练，试试先转后升。':`第${s.beat}拍：${({turn:'转庭',rise:'升台',rest:'停拍'} as Record<string,string>)[note]}。`;
   }
   if(id==='repair'){
    if(!this.ready())throw Error(this.hint().message);
    if(!this.together)throw Error('沿真正接通的路，把另一位旅人带到花床旁，一起种下微光。');
    s.completed=true;s.playing=false;return l.story;
   }
   throw Error('先走近一点，再看看能帮什么忙。');
  });
 }
 hint():{message:string;target?:string}{
  const s=this.state,id=this.level.id;
  if(s.completed)return {message:this.level.story};
  const hints:Record<string,()=>string>={
   '1-1':()=>'走近根台，向右引一节芽，沿石板到花床，再种下微光。',
   '1-2':()=>'从根台向上绕：上、右、右、下；或从下方对称绕行。四节芽都要连续。',
   '1-3':()=>'进入庭院中心，连人带花园转90°。原来的西口会接向北岸。',
   '1-4':()=>!this.flag('latch')?'露薇在外庭扳住重杆；换小苔灵过桥穿低拱，到轻踏板；再换露薇过南门固定门闩。':!this.flag('home')?'露薇取回内庭的门铃，带到鼹鼠家门。交还铃铛后，花门就会打开。':'接上小苔灵，穿过鼹鼠旁已打开的花门，到小花园中央一起播种。',
   '2-1':()=>!this.flag('care')?'保持低水位，走南侧石阶取清露，回浮台把露珠留给花心。':'水位调到中位，浮台会接上右侧花岸；高位通往可选芦苇湾。',
   '2-2':()=>s.items.mirrorB.tile!==cell(1,0)?'露薇搬起右下镜叶，走到上方槽(1,0)放下。':'把两片镜叶都转成斜向上反射：光先向上，再向右绕过石壁。',
   '2-3':()=>!this.flag('raised')?'露薇走上花台，小苔灵留在琴台。转庭必须先于升台；可以单步试奏。':!this.flag('latch')?'正确朝向应向北。若先升后转，重新排练；到北岸后固定便道。':'固定便道已经打开，操控小苔灵走回露薇身边，再播种。',
   '2-4':()=>!this.flag('plant')?'走上移动花园种蜜花，再在靠近左岸时邀请光虫。':s.items.bug.tile!==modCell('boat')&&!this.flag('pollinated')?'把花园停近左岸，邀请光虫落在蜜花上。':!this.flag('pollinated')?'载光虫一起移到右岸，再邀请它飞向核心花岸授粉。':'远岸成熟了，沿接上的石板过去，一起播种。',
   '3-1':()=>!this.flag('window')?'让小苔灵提灯穿南侧低通道，到右下照孔，灯朝上；露薇穿门后移开石窗。':'灯井已经自亮，提灯沿低通道回来。两人带灯在核心旁会合。',
   '3-2':()=>s.items.sunPost.tile!==cell(0,0)?'露薇搬起左岸日影柱，放到起点日影槽(0,0)，先接上去中台的路。':s.items.moonPost.tile!==cell(3,-1)?'把左岸月影柱带过日影路，放在右上月影槽(3,-1)，再回起点。':'固定日影再切月光；或先固定月影再切日光。留影保存的是当时的实际形状。',
   '3-3':()=>!this.connected()?'保持分水庭0°，沿北口去藤根，引芽：右、右、右、下，接往花台。':!this.flag('root')?'乘东侧花台上升取露珠，降回藤根，把露珠留给它。':'藤根已经自给，转分水庭到90°，水同时去花台与苔藓。沿固定根阶再升高，走南侧影路。',
   '3-4':()=>!this.flag('root')?'从内庭北口到根台，引芽向右三节，固定叶阶。':!this.flag('rain')?'小苔灵沿南侧低拱去送水庭，转90°接水；露薇搬起北台重镜叶，走上花台。':!this.flag('star')?'露薇带镜叶升高，放在右岸高槽。沿右侧石阶到外庭，将光源转90°朝北。':s.turns.inner!==1?'把内庭转到90°，接上花台到藤根的回流通路。':s.turns.water!==1?'把送水庭恢复到90°，继续给花台供水。':!this.beamHits(-4,0)?'保持高槽镜叶与外庭朝向，让光实际到达西侧核心。':!this.together?'切换角色，沿已经固定的归途，让两位在西岸会合。':'路、水与光都已相连，一起种下微光吧。',
  };
  return {message:hints[id]?.()??this.level.intro};
 }
}
