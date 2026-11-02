import type {GardenLevel,Point,Tile} from './types';
import {oval,softMaterial,smallLeaf} from '../game/creatureArt';

export const TERRAIN_RISE=48;
export interface LandscapeView{
 c:CanvasRenderingContext2D;scale:number;time:number;particles:boolean;
 project:(point:Point)=>{x:number;y:number};images:Map<string,HTMLImageElement>;
}
export function terrainSteps(tiles:Tile[]){
 const pairs:[Tile,Tile][]=[];
 for(const a of tiles)for(const [dx,dz]of [[1,0],[0,1]]){
  const b=tiles.find(b=>b.x===a.x+dx&&b.z===a.z+dz);
  if(b&&!a.solid&&!b.solid&&Math.abs(a.h-b.h)>.01&&Math.abs(a.h-b.h)<=1)pairs.push(a.h<b.h?[a,b]:[b,a]);
 }
 return pairs;
}
export function faceDepth(tile:Tile,neighbor:Tile|undefined,base:number){
 return neighbor?Math.max(0,(tile.h-neighbor.h)*TERRAIN_RISE):Math.max(12,base+tile.h*TERRAIN_RISE);
}
function polygon(c:CanvasRenderingContext2D,points:{x:number;y:number}[]){c.beginPath();points.forEach((p,i)=>i?c.lineTo(p.x,p.y):c.moveTo(p.x,p.y));c.closePath();}
function shoreline(c:CanvasRenderingContext2D,points:{x:number;y:number}[]){
 const first=points[0],last=points[points.length-1];c.beginPath();c.moveTo((first.x+last.x)/2,(first.y+last.y)/2);
 points.forEach((p,i)=>{const next=points[(i+1)%points.length];c.quadraticCurveTo(p.x,p.y,(p.x+next.x)/2,(p.y+next.y)/2);});c.closePath();
}
function hull(points:Point[]){
 const sorted=[...points].sort((a,b)=>a.x-b.x||a.z-b.z),cross=(a:Point,b:Point,c:Point)=>(b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x);
 const half=(list:Point[])=>{const result:Point[]=[];for(const p of list){while(result.length>=2&&cross(result[result.length-2],result[result.length-1],p)<=0)result.pop();result.push(p);}return result;};
 const low=half(sorted),high=half([...sorted].reverse());return [...low.slice(0,-1),...high.slice(0,-1)];
}
const pondOutlines=new WeakMap<GardenLevel,Point[]>();
export function pondFootprint(level:GardenLevel){
 const cached=pondOutlines.get(level);if(cached)return cached;
 const points=[...level.tiles,...level.modules.flatMap(m=>m.shape.flatMap(([x,z])=>[0,m.distance??0].map(shift=>({x:m.x+x+(m.axis==='x'?shift:0),z:m.z+z+(m.axis==='z'?shift:0),h:0}))))];
 const outline=hull(points.flatMap(p=>Array.from({length:8},(_,i)=>({x:p.x+Math.cos(i*Math.PI/4)*1.7,z:p.z+Math.sin(i*Math.PI/4)*1.7,h:0}))));pondOutlines.set(level,outline);return outline;
}
/** A stone-lined lake, with currents and vegetation anchored in world space. */
export function drawPond(v:LandscapeView,level:GardenLevel,tiles:Tile[],waterHeight:number){
 const {c,project,scale:s,time}=v,outline=pondFootprint(level).map(p=>project({...p,h:waterHeight}));
 c.save();shoreline(c,outline);c.lineJoin='round';c.strokeStyle='#839c8a';c.lineWidth=11*s;c.stroke();c.strokeStyle='#c8cfac';c.lineWidth=6*s;c.stroke();
 for(let i=0;i<outline.length;i++){const a=outline[i],b=outline[(i+1)%outline.length],count=Math.ceil(Math.hypot(b.x-a.x,b.y-a.y)/(18*s));for(let n=0;n<count;n++){const f=n/count,p={x:a.x+(b.x-a.x)*f,y:a.y+(b.y-a.y)*f};oval(c,p.x,p.y,(6+(n+i)%4)*s,(3+(n*3+i)%3)*s,softMaterial(c,p.x,p.y,12*s,'#d2d6b7','#a4b397','#738f82'));}}
 shoreline(c,outline);
 const ys=outline.map(p=>p.y),water=c.createLinearGradient(0,Math.min(...ys),0,Math.max(...ys));water.addColorStop(0,'#bbdfd3');water.addColorStop(.42,'#8ac2c6');water.addColorStop(1,'#6ca4b2');c.fillStyle=water;c.fill();c.strokeStyle='#dfeddbac';c.lineWidth=1.2*s;c.stroke();c.clip();
 const pigment=v.images.get('water-pigment');if(pigment?.complete&&pigment.naturalWidth){c.save();c.globalAlpha=.4;const texture=c.createPattern(pigment,'repeat');if(texture){c.fillStyle=texture;c.fillRect(Math.min(...outline.map(p=>p.x)),Math.min(...ys),Math.max(...outline.map(p=>p.x))-Math.min(...outline.map(p=>p.x)),Math.max(...ys)-Math.min(...ys));}c.restore();}
 const minX=Math.floor(Math.min(...level.tiles.map(t=>t.x)))-1,maxX=Math.ceil(Math.max(...level.tiles.map(t=>t.x),...level.modules.map(m=>m.x+(m.distance??0))))+2;
 const minZ=Math.floor(Math.min(...level.tiles.map(t=>t.z)))-1,maxZ=Math.ceil(Math.max(...level.tiles.map(t=>t.z)))+2;
 for(let x=minX;x<=maxX;x++)for(let z=minZ;z<=maxZ;z++){
  const seed=Math.abs(x*37+z*61),near=tiles.some(t=>Math.abs(t.x-x)+Math.abs(t.z-z)<1.6),p=project({x:x+.23,z:z+.15,h:waterHeight});
  c.strokeStyle=seed%3?'#e4f7e844':'#477f9d24';c.lineWidth=.8*s;c.beginPath();c.ellipse(p.x+Math.sin(time*.0005+seed)*3*s,p.y, (11+seed%13)*s,(3+seed%4)*s,-.08,0,Math.PI*1.6);c.stroke();
  if(near)continue;
  if(seed%7===0){
   const im=v.images.get('lilypad');if(im?.complete&&im.naturalWidth){const w=(19+seed%11)*s;c.drawImage(im,p.x-w/2,p.y-w*.25,w,w*.54);}
   if(seed%2===0){oval(c,p.x,p.y-4*s,3*s,2*s,'#f4d9c0');oval(c,p.x,p.y-5*s,1.2*s,1.3*s,'#ffe7ae');}
  }
  if(seed%13===0){for(let n=0;n<4;n++){const dx=(n-1.5)*4*s,top=p.y-(21+n%2*12)*s;c.strokeStyle='#668d70';c.lineWidth=1.3*s;c.beginPath();c.moveTo(p.x,p.y);c.quadraticCurveTo(p.x+dx,top+11*s,p.x+dx,top);c.stroke();c.strokeStyle='#9f8b5e';c.lineWidth=3*s;c.beginPath();c.moveTo(p.x+dx,top);c.lineTo(p.x+dx,top-5*s);c.stroke();}}
  if(v.particles&&seed%11===0){const phase=(time/4000+seed*.13)%1;c.globalAlpha=(1-phase)*.45;c.strokeStyle='#f0f9ed';c.beginPath();c.ellipse(p.x,p.y,(4+phase*15)*s,(1+phase*5)*s,0,0,Math.PI*2);c.stroke();c.globalAlpha=1;}
 }
 c.restore();
}

/** Treads only span adjacent floors that the actual movement graph can traverse. */
export function drawTerrainSteps(v:LandscapeView,tiles:Tile[]){
 const {c,project,scale:s}=v;
 for(const [low,high]of terrainSteps(tiles)){
  const dx=high.x-low.x,dz=high.z-low.z,start={x:low.x+dx*.10,z:low.z+dz*.10,h:low.h},count=4;
  for(let i=0;i<count;i++){
   const f0=i/count*.8,f1=(i+1)/count*.8,h=low.h+(high.h-low.h)*(i+1)/count,width=.29;
   const corners=[[-width,f0],[width,f0],[width,f1],[-width,f1]].map(([side,f])=>project({x:start.x+dx*f-dz*side,z:start.z+dz*f+dx*side,h}));
   const drop=(high.h-low.h)/count*TERRAIN_RISE*s;c.save();polygon(c,[corners[0],corners[1],{x:corners[1].x,y:corners[1].y+drop},{x:corners[0].x,y:corners[0].y+drop}]);c.fillStyle='#9b9f82';c.fill();
   polygon(c,corners);c.fillStyle=i%2?'#ddd6b9':'#cbcbb0';c.fill();c.save();c.clip();const stone=v.images.get('paving-valley');if(stone?.complete&&stone.naturalWidth){const xs=corners.map(p=>p.x),ys=corners.map(p=>p.y);c.globalAlpha=.72;c.drawImage(stone,Math.min(...xs),Math.min(...ys),Math.max(...xs)-Math.min(...xs),Math.max(...ys)-Math.min(...ys));}c.restore();c.strokeStyle='#f8ebc594';c.lineWidth=.7*s;c.stroke();c.restore();
  }
 }
}

export function runoffSource(level:GardenLevel,tiles:Tile[]){
 const candidates=tiles.filter(t=>!t.module&&!t.small&&!t.solid&&t.h>=(level.chapter==='pond'?0:1)&&!tiles.some(n=>n.x===t.x&&n.z===t.z+1)&&!level.marks.some(m=>m.tile===t.id));
 return candidates.sort((a,b)=>b.h-a.h||b.x-a.x)[0];
}
export function drawRunoff(v:LandscapeView,level:GardenLevel,tiles:Tile[],waterHeight:number){
 const {c,project,scale:s,time}=v,source=runoffSource(level,tiles);if(!source)return;
 const lip={x:source.x,z:source.z+.5,h:source.h},p=project(lip),bottom=project({...lip,h:level.chapter==='pond'?waterHeight:source.h-2.8});
 if(bottom.y-p.y<5*s)return;
 const head=project({...lip,z:lip.z-.9}),width=10*s;
 c.save();c.lineCap='round';c.strokeStyle='#6b9f9b99';c.lineWidth=11*s;c.beginPath();c.moveTo(head.x,head.y);c.quadraticCurveTo(p.x+6*s,p.y-8*s,p.x,p.y);c.stroke();c.strokeStyle='#c6efdf';c.lineWidth=4.5*s;c.stroke();
 const fall=c.createLinearGradient(p.x,p.y,p.x,bottom.y);fall.addColorStop(0,'#d1f0e5e6');fall.addColorStop(.5,'#91cad6c7');fall.addColorStop(1,'#d0ede066');c.fillStyle=fall;
 c.beginPath();c.moveTo(p.x-width*.45,p.y);c.bezierCurveTo(p.x-width*.6,p.y+20*s,bottom.x-width*.8,bottom.y-12*s,bottom.x-width*.9,bottom.y);c.lineTo(bottom.x+width*.9,bottom.y);c.bezierCurveTo(bottom.x+width*.4,bottom.y-20*s,p.x+width*.3,p.y+20*s,p.x+width*.45,p.y);c.closePath();c.fill();
 c.strokeStyle='#effdecaa';c.lineWidth=1.1*s;
 for(let i=0;i<3;i++){const y=p.y+((time*.025+i*23)%(Math.max(10,bottom.y-p.y)));c.beginPath();c.moveTo(p.x+(i-1)*3*s,y);c.lineTo(p.x+(i-1)*3*s,y+10*s);c.stroke();}
 oval(c,bottom.x,bottom.y+2*s,21*s,6*s,softMaterial(c,bottom.x,bottom.y,24*s,'#d1e9d6','#82b8bc','#688f9e'));
 for(let i=0;i<3;i++){c.beginPath();c.ellipse(bottom.x,bottom.y,(9+i*6+Math.sin(time*.001+i))*s,(2+i*1.7)*s,0,0,Math.PI*1.8);c.stroke();}
 c.restore();
}

export function drawWetPaving(v:LandscapeView,tile:Tile){
 const {c,project,scale:s}=v,seed=Math.abs(tile.x*17+tile.z*29);if(seed%4)return;
 const p=project(tile);c.save();c.globalAlpha=.36;oval(c,p.x-4*s,p.y+2*s,14*s,5*s,softMaterial(c,p.x,p.y,20*s,'#dbf6ec','#7aafb5','#5a979f'),-.1);c.strokeStyle='#d8eee3';c.lineWidth=.8*s;c.beginPath();c.ellipse(p.x-5*s,p.y+2*s,10*s,3*s,-.1,Math.PI,Math.PI*1.8);c.stroke();smallLeaf(c,p.x+9*s,p.y+3*s,.22,.4);c.restore();
}

export function drawShallowStone(v:LandscapeView,tile:Tile){
 const {c,project,scale:s,time}=v,p=project(tile);
 c.save();polygon(c,[{x:p.x,y:p.y-17.5*s},{x:p.x+35*s,y:p.y},{x:p.x,y:p.y+17.5*s},{x:p.x-35*s,y:p.y}]);c.clip();
 c.fillStyle='#8dc2c6d9';c.fill();
 for(let i=0;i<3;i++){const shift=(time*.004+i*9)%28;c.strokeStyle='#e0f4e399';c.lineWidth=.8*s;c.beginPath();c.moveTo(p.x-31*s,p.y+(shift-14)*s);c.quadraticCurveTo(p.x,p.y+(shift-19)*s,p.x+30*s,p.y+(shift-14)*s);c.stroke();}
 oval(c,p.x+1*s,p.y+4*s,22*s,9*s,'#528b9266');
 oval(c,p.x,p.y+1*s,20*s,9*s,softMaterial(c,p.x-5*s,p.y-2*s,25*s,'#e0dfbf','#b9c2a7','#879f91'));
 const stone=v.images.get('paving-pond');if(stone?.complete&&stone.naturalWidth){c.save();c.beginPath();c.ellipse(p.x,p.y,19*s,8*s,0,0,Math.PI*2);c.clip();c.globalAlpha=.7;c.drawImage(stone,p.x-22*s,p.y-9*s,44*s,18*s);c.restore();}
 c.strokeStyle='#e1e5c8b0';c.lineWidth=.8*s;c.beginPath();c.ellipse(p.x,p.y,19*s,8*s,0,Math.PI*.95,Math.PI*1.9);c.stroke();c.restore();
}
