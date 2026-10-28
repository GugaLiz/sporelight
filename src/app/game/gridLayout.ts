import type { Level } from './levels';
export interface GridPosition { x:number; z:number }
export interface GridPoint extends GridPosition { h:number }
export interface GridTile extends GridPoint { key:string; room?:string; edges:number[]; solid?:boolean; prop?:'arch'|'rock'|'lantern'; gap?:boolean }
export interface GridLayout { tiles:Map<string,GridTile>; nodes:Record<string,GridPoint>; level:Level; paths:GridPosition[][] }
type NodeMap=Record<string,[number,number,number]>;
const MAPS:Record<string,NodeMap>={
 '1-1':{start:[1,6,0],fork:[5,6,0],fern:[5,1,1],stone:[10,6,1],end:[10,1,2]},
 '1-2':{start:[1,6,0],north:[5,2,1],pollen:[11,2,1],east:[6,7,0],end:[12,7,1]},
 '1-3':{start:[1,6,0],pivot:[6,6,1],dew:[6,1,2],leaf:[11,6,1],end:[11,1,3]},
 '1-4':{start:[1,7,0],near:[5,7,0],home:[9,7,0],garden:[9,2,1],end:[13,7,1]},
 '2-1':{start:[1,6,0],upper:[5,6,2],west:[6,1,2],east:[7,10,2],end:[12,5,2]},
 '2-2':{start:[1,7,0],mirrorA:[5,2,1],pool:[10,2,1],mirrorB:[6,7,0],crystal:[12,1,3],end:[12,7,2]},
 '2-3':{start:[1,7,0],drum:[6,6,1],echo:[6,1,2],lift:[10,6,1],end:[14,6,3]},
 '2-4':{start:[1,8,1],reed:[5,8,1],lotus:[9,8,1],bell:[13,8,3],home:[13,2,3],end:[17,8,3]},
 '3-1':{start:[1,8,0],lampA:[5,8,0],quiet:[5,3,1],lampB:[10,8,1],root:[14,8,1],secret:[14,3,2],lampC:[19,8,2],end:[19,3,3]},
 '3-2':{start:[1,6,0],dial:[6,6,1],sun:[6,1,2],moon:[11,6,0],end:[11,1,2]},
 '3-3':{start:[1,8,0],pump:[5,8,0],vine:[10,8,1],lift:[14,8,1],dew:[18,8,3],lily:[5,2,1],rest:[10,2,1],end:[15,2,3]},
 '3-4':{start:[7,7,1],a:[3,7,1],moon:[3,12,0],b:[7,3,1],leaf:[3,3,2],c:[11,7,1],star:[11,3,3],d:[7,11,1],rain:[11,11,2],gate:[7,-1,3],end:[7,-5,3]},
};
const BENDS:Record<string,Record<string,GridPosition[]>>={
 '1-2':{'start:north':[{x:1,z:2}],'start:east':[{x:3,z:6},{x:3,z:7}]},
 '1-3':{'pivot:end':[{x:9,z:6},{x:9,z:1}]},
 '2-2':{'start:mirrorA':[{x:1,z:2}]},
 '3-2':{'dial:end':[{x:9,z:6},{x:9,z:1}]},
 '3-4':{'start:gate':[{x:9,z:7},{x:9,z:-1}]},
};
export const gridKey=(p:GridPosition)=>`${p.x},${p.z}`;
export const sameTile=(a:GridPosition,b:GridPosition)=>a.x===b.x&&a.z===b.z;
export type GridDirection='up'|'down'|'left'|'right';
export const GRID_DIRECTIONS:Record<GridDirection,GridPosition>={up:{x:0,z:-1},down:{x:0,z:1},left:{x:-1,z:0},right:{x:1,z:0}};
export function buildGridLayout(level:Level,vars:Record<string,string>={}):GridLayout {
 const spec=MAPS[level.id];const tiles=new Map<string,GridTile>();
 const nodes=Object.fromEntries(Object.entries(spec).map(([id,[x,z,h]])=>[id,{x,z,h}]));
 if(level.lift)nodes[level.lift.node].h=vars[level.lift.node]==='high'?level.lift.high:level.lift.low;
 const paths:GridPosition[][]=[];
 for(const [id,point]of Object.entries(nodes))for(let dx=-1;dx<=1;dx++)for(let dz=-1;dz<=1;dz++){
  const p={x:point.x+dx,z:point.z+dz,h:point.h};const key=gridKey(p);
  tiles.set(key,{...p,key,room:id,edges:[],solid:dx===-1&&dz===-1,prop:dx===-1&&dz===-1?(Object.keys(nodes).indexOf(id)%3===1?'arch':'rock'):undefined});
 }
 level.edges.forEach((edge,index)=>{
  if(edge.jump){paths[index]=[];return;}
  const a=nodes[edge.from],b=nodes[edge.to];
  const bends=BENDS[level.id]?.[`${edge.from}:${edge.to}`]??[{x:b.x,z:a.z}];
  const path:GridPosition[]=[a];
  for(const target of [...bends,b]){let current=path[path.length-1];while(!sameTile(current,target)){current={x:current.x+Math.sign(target.x-current.x),z:current.z};if(current.x===path[path.length-1].x)current={x:current.x,z:current.z+Math.sign(target.z-current.z)};path.push(current);}}
  paths[index]=path;
  path.forEach((p,i)=>{const key=gridKey(p);let tile=tiles.get(key);if(!tile){tile={...p,key,h:Math.round(a.h+(b.h-a.h)*i/Math.max(1,path.length-1)),edges:[]};tiles.set(key,tile);}tile.edges.push(index);});
 });
 // A genuine one-cell break teaches Space; it cannot be crossed by walking.
 if(level.id==='1-1'){const tile=tiles.get('10,3');if(tile&&!tile.room)tile.gap=true;}
 return {tiles,nodes,level,paths};
}

export interface GridView { width:number;height:number;scale:number;originX:number;originY:number;tileWidth:number;tileHeight:number }
export function makeGridView(layout:GridLayout,width:number,height:number,player:GridPoint):GridView {
 const tileWidth=78,tileHeight=39;
 const raw=(p:GridPoint)=>({x:(p.x-p.z)*tileWidth/2,y:(p.x+p.z)*tileHeight/2-p.h*25});
 if(width<height){const scale=Math.min(.84,Math.max(.68,width/510));const p=raw(player);return {width,height,scale,originX:width*.38-p.x*scale,originY:height*.49-p.y*scale,tileWidth,tileHeight};}
 const points=[...layout.tiles.values()].map(raw);const minX=Math.min(...points.map(p=>p.x)),maxX=Math.max(...points.map(p=>p.x));const minY=Math.min(...points.map(p=>p.y)),maxY=Math.max(...points.map(p=>p.y));
 const scale=Math.min(1.28,865/(maxX-minX+90),445/(maxY-minY+100));
 return {width,height,scale,originX:width*.48-(minX+maxX)/2*scale,originY:height*.57-(minY+maxY)/2*scale,tileWidth,tileHeight};
}
export function projectTile(p:GridPoint,view:GridView){return {x:view.originX+(p.x-p.z)*view.tileWidth/2*view.scale,y:view.originY+((p.x+p.z)*view.tileHeight/2-p.h*25)*view.scale};}
