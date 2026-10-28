import { GameModel, type ActionResult, type RunState } from './model';
import { buildGridLayout, gridKey, sameTile, GRID_DIRECTIONS, type GridPosition, type GridPoint, type GridDirection, type GridTile } from './gridLayout';
import type { Level } from './levels';
export interface GridStep { position:GridPosition; jump:boolean }

/** Physical floor tiles adapt the existing puzzle rules without allowing shortcuts. */
export class GridWorld {
 readonly model:GameModel;
 layout:ReturnType<typeof buildGridLayout>;
 position:GridPosition;
 constructor(level:Level,saved?:Partial<RunState>|null) {
  this.model=new GameModel(level,saved);this.layout=buildGridLayout(level,this.model.state.vars);
  const fallback=this.layout.nodes[this.model.state.node];const previous=this.model.state.gridPosition;
  this.position=previous&&this.tileOpen(previous)?{...previous}:{x:fallback.x,z:fallback.z};
  const savedRoom=this.layout.tiles.get(gridKey(this.position))?.room;
  const wrongRoom=!!savedRoom&&savedRoom!==this.model.state.node;
  if(previous&&(wrongRoom||!this.pathTo(fallback)))this.position={x:fallback.x,z:fallback.z};
  this.sync();
 }
 get point():GridPoint { return this.layout.tiles.get(gridKey(this.position))??{...this.position,h:0}; }
 private sync(){this.model.state.gridPosition={...this.position};}
 tileVisible(tile:GridTile) {return tile.room?this.model.isVisible(tile.room):tile.edges.some(i=>{const e=this.layout.level.edges[i];return this.model.isVisible(e.from)&&this.model.isVisible(e.to);});}
 ownerOpen(tile:GridTile) {
  if(tile.room&&this.model.isVisible(tile.room))return true;
  return tile.edges.some(i=>{const e=this.layout.level.edges[i];return this.model.edgeOpen(e.from,e.to);});
 }
 tileOpen(p:GridPosition) {const tile=this.layout.tiles.get(gridKey(p));return !!tile&&!tile.solid&&!tile.gap&&this.tileVisible(tile)&&this.ownerOpen(tile);}
 private transition(from:GridPosition,to:GridPosition,anchor:string) {
  if(!this.tileOpen(to))return null;
  const a=this.layout.tiles.get(gridKey(from))!,b=this.layout.tiles.get(gridKey(to))!;
  if(Math.abs(a.h-b.h)>1)return null;
  return b.room&&b.room!==anchor?(this.model.canEnter(b.room,anchor)?b.room:null):anchor;
 }
 canStep(to:GridPosition,from=this.position,anchor=this.model.state.node) {
  return Math.abs(to.x-from.x)+Math.abs(to.z-from.z)===1&&this.transition(from,to,anchor)!==null;
 }
 canJump(to:GridPosition,from=this.position,anchor=this.model.state.node) {
  const dx=to.x-from.x,dz=to.z-from.z,distance=Math.abs(dx)+Math.abs(dz);
  if((dx&&dz)||distance<1||distance>2||!this.tileOpen(to))return false;
  const a=this.layout.tiles.get(gridKey(from))!,b=this.layout.tiles.get(gridKey(to))!;
  if(Math.abs(a.h-b.h)>2||b.room&&b.room!==anchor&&!this.model.canEnter(b.room,anchor))return false;
  if(distance===1)return !b.solid;
  const middle=this.layout.tiles.get(gridKey({x:from.x+Math.sign(dx),z:from.z+Math.sign(dz)}));
  return !!middle&&!!middle.gap&&!middle.solid&&this.ownerOpen(middle);
 }
 destination(direction:GridDirection,jump=false):GridPosition|null {
  const d=GRID_DIRECTIONS[direction];const next={x:this.position.x+d.x,z:this.position.z+d.z};
  if(!jump)return this.canStep(next)?next:null;
  const far={x:this.position.x+d.x*2,z:this.position.z+d.z*2};
  if(this.canJump(far))return far;
  return this.canJump(next)?next:null;
 }
 commit(to:GridPosition,jump=false):ActionResult {
  if(!(jump?this.canJump(to):this.canStep(to)))return {ok:false,message:'这里没有可踩的石砖，墙壁和未接通的桥都不能穿过。'};
  const tile=this.layout.tiles.get(gridKey(to))!;
  const result=tile.room&&tile.room!==this.model.state.node?this.model.move(tile.room):this.model.moveWithinGrid(to);
  if(result.ok){this.position={...to};this.sync();}
  return result;
 }
 actions() {return this.nearMechanism()?this.model.actions():[];}
 nearMechanism() {
  const p=this.layout.nodes[this.model.state.node];
  return Math.abs(p.x-this.position.x)+Math.abs(p.z-this.position.z)<=1;
 }
 atNode(id:string){return sameTile(this.position,this.layout.nodes[id]);}
 act(action:string,time:number,lowMotion:boolean):ActionResult {
  if(!this.nearMechanism())return {ok:false,message:'再走近花床一格，就可以与它互动。'};
  this.sync();const result=this.model.act(action,time,lowMotion);
  if(result.ok&&result.lifted)this.layout=buildGridLayout(this.model.level,this.model.state.vars);
  if(result.ok&&result.jumped){const p=this.layout.nodes[this.model.state.node];this.position={x:p.x,z:p.z};this.sync();}
  return result;
 }
 undo(){if(!this.model.undo())return false;this.layout=buildGridLayout(this.model.level,this.model.state.vars);const p=this.model.state.gridPosition??this.layout.nodes[this.model.state.node];this.position={x:p.x,z:p.z};this.sync();return true;}
 pathTo(goal:GridPosition,allowJumps=true):GridStep[]|null {
  type State={p:GridPosition;anchor:string;path:GridStep[]};
  const queue:State[]=[{p:this.position,anchor:this.model.state.node,path:[]}];
  const seen=new Set([`${gridKey(this.position)}:${this.model.state.node}`]);
  for(let i=0;i<queue.length;i++){
   const current=queue[i];if(sameTile(current.p,goal))return current.path;
   for(const d of Object.values(GRID_DIRECTIONS))for(const distance of [1,2]){
    const target={x:current.p.x+d.x*distance,z:current.p.z+d.z*distance};
    const walking=distance===1&&this.canStep(target,current.p,current.anchor);
    const jumping=!walking&&allowJumps&&this.canJump(target,current.p,current.anchor);
    if(!walking&&!jumping)continue;
    const tile=this.layout.tiles.get(gridKey(target))!;const anchor=tile.room??current.anchor;const key=`${gridKey(target)}:${anchor}`;
    if(seen.has(key))continue;seen.add(key);queue.push({p:target,anchor,path:[...current.path,{position:target,jump:jumping}]});
   }
  }
  return null;
 }
 pathToNode(id:string){const p=this.layout.nodes[id];return p?this.pathTo(p):null;}
}
