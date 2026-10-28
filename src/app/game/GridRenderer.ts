import { GridWorld } from './GridWorld';
import { makeGridView, projectTile, gridKey, GRID_DIRECTIONS, type GridPoint, type GridPosition, type GridView, type GridTile } from './gridLayout';
import { CHARACTER_FILES, jumpHeight, type CharacterPose } from './characterMotion';
import type { SaveData } from '../types';

export interface GridRenderState {
 time:number;player:GridPoint;pose:CharacterPose;travel?:{progress:number;jump:boolean;from:GridPoint;to:GridPoint}|null;
 hint?:string;target?:GridPosition|null;clueUntil:number;actionElapsed?:number;
}
export class GridRenderer {
 readonly ctx:CanvasRenderingContext2D;
 readonly images=new Map<string,HTMLImageElement>();
 view:GridView;
 private width=1280;private height=720;
 private settings:SaveData['settings'];
 private lastState?:GridRenderState;
 constructor(private canvas:HTMLCanvasElement,readonly world:GridWorld,settings:SaveData['settings']) {
  this.ctx=canvas.getContext('2d')!;this.settings=settings;
  const load=(key:string,url:string)=>{const im=new Image();im.src=url;this.images.set(key,im);};
  for(const key of ['grass','stone','cliff','moss-stone','stairs','rock','lantern','flowers','bush','lilypad','crystal','bridge','arch'])load(key,`./images/grid-world/${key}.png`);
  for(const key of ['wall-left','wall-right'])load(key,`./images/grid-world/${key}.jpg`);
  for(const key of ['soil','flower','bloom','moss','light','vine','lily','lily-open','bug'])load(key,`./images/production/${key}.png`);
  for(const key of CHARACTER_FILES)load(`actor:${key}`,`./images/material-ready/${key}.png`);
  for(const key of ['spore','trail','growth','glow'])load(`fx:${key}`,`./images/material-ready/fx-${key}.png`);
  load('background',`./images/grid-world/sky-${world.model.level.chapter}.jpg`);
  this.view=makeGridView(world.layout,1280,720,world.point);this.configure(settings);
 }
 configure(settings:SaveData['settings']) {
  this.settings=settings;this.width=this.canvas.clientWidth||1280;this.height=this.canvas.clientHeight||720;
  const ratio=settings.quality==='hd'?Math.min(devicePixelRatio||1,2):settings.quality==='soft'?.8:1;
  const pixelWidth=Math.round(this.width*ratio),pixelHeight=Math.round(this.height*ratio);
  const resized=this.canvas.width!==pixelWidth||this.canvas.height!==pixelHeight;
  if(resized){this.canvas.width=pixelWidth;this.canvas.height=pixelHeight;}
  this.ctx.setTransform(ratio,0,0,ratio,0,0);
  if(resized&&this.lastState)this.draw(this.lastState);
 }
 private picture(key:string,x:number,y:number,width:number,anchor=.9,alpha=1) {
  const im=this.images.get(key);if(!im?.complete||!im.naturalWidth)return;
  const height=width*im.naturalHeight/im.naturalWidth;
  this.ctx.save();this.ctx.globalAlpha=alpha;this.ctx.drawImage(im,x-width/2,y-height*anchor,width,height);this.ctx.restore();
 }
 private polygon(points:number[][],fill:string,stroke?:string) {
  const c=this.ctx;c.beginPath();points.forEach(([x,y],i)=>i?c.lineTo(x,y):c.moveTo(x,y));c.closePath();c.fillStyle=fill;c.fill();
  if(stroke){c.strokeStyle=stroke;c.lineWidth=.8;c.stroke();}
 }
 private floor(tile:GridTile) {
  const {ctx:c,view:v}=this;const p=projectTile(tile,v),w=v.tileWidth*v.scale,h=v.tileHeight*v.scale;
  const depth=(77+tile.h*14)*v.scale;
  this.polygon([[p.x-w/2,p.y],[p.x,p.y+h/2],[p.x,p.y+h/2+depth],[p.x-w/2,p.y+depth]],'#8c8768','#6d73584d');
  this.polygon([[p.x,p.y+h/2],[p.x+w/2,p.y],[p.x+w/2,p.y+depth],[p.x,p.y+h/2+depth]],'#70765b','#5e68514d');
  const left=this.images.get('wall-left'),right=this.images.get('wall-right');
  if(left?.complete&&left.naturalWidth){c.save();c.transform(w/2/256,h/2/256,0,depth/160,p.x-w/2,p.y);c.drawImage(left,0,0);c.restore();}
  if(right?.complete&&right.naturalWidth){c.save();c.transform(w/2/256,-h/2/256,0,depth/160,p.x,p.y+h/2);c.drawImage(right,0,0);c.restore();}
  // Masonry seams and small vines extend the real tile's sides into a ruin column.
  c.save();c.strokeStyle='#d2c49140';c.lineWidth=.7;
  for(let y=13*v.scale;y<depth;y+=16*v.scale){c.beginPath();c.moveTo(p.x-w/2,p.y+y);c.lineTo(p.x,p.y+h/2+y);c.lineTo(p.x+w/2,p.y+y);c.stroke();}
  c.strokeStyle='#596d465c';c.lineWidth=2*v.scale;
  for(let i=0;i<2;i++){const q=(tile.x*13+tile.z*7+i*23)%43/43;c.beginPath();c.moveTo(p.x-w/2+q*w/2,p.y+q*h/2+9*v.scale);c.quadraticCurveTo(p.x-w/2+q*w/2+4,p.y+depth*.55,p.x-w/2+q*w/2-2,p.y+depth*.85);c.stroke();}c.restore();
  const texture=tile.room?(tile.solid?'grass':(tile.x+tile.z)%4===0?'moss-stone':'stone'):(tile.x+tile.z)%4===0?'grass':'stone';
  const im=this.images.get(texture);
  if(im?.complete&&im.naturalWidth){const width=w*1.045,height=width*im.naturalHeight/im.naturalWidth;c.drawImage(im,p.x-width/2,p.y-width*.265,width,height);}
  else this.polygon([[p.x,p.y-h/2],[p.x+w/2,p.y],[p.x,p.y+h/2],[p.x-w/2,p.y]],'#c1c6a0');
  if(!tile.solid&&tile.edges.length&&Object.values(GRID_DIRECTIONS).some(d=>{const t=this.world.layout.tiles.get(gridKey({x:tile.x+d.x,z:tile.z+d.z}));return t&&t.h<tile.h;}))this.picture('stairs',p.x,p.y+h*.43,w*.87,.65);
 }
 private tileOutline(tile:GridPoint,color:string,width=2) {
  const p=projectTile(tile,this.view),w=this.view.tileWidth*this.view.scale,h=this.view.tileHeight*this.view.scale;
  const c=this.ctx;c.save();c.strokeStyle=color;c.lineWidth=width;c.beginPath();c.moveTo(p.x,p.y-h/2);c.lineTo(p.x+w/2,p.y);c.lineTo(p.x,p.y+h/2);c.lineTo(p.x-w/2,p.y);c.closePath();c.stroke();c.restore();
 }
 hit(x:number,y:number):GridTile|undefined {
  return [...this.world.layout.tiles.values()].filter(t=>!t.gap&&!t.solid&&this.world.tileVisible(t)&&this.world.ownerOpen(t)).sort((a,b)=>(b.x+b.z)-(a.x+a.z)).find(t=>{const p=projectTile(t,this.view);return Math.abs(x-p.x)/(this.view.tileWidth*this.view.scale/2)+Math.abs(y-p.y)/(this.view.tileHeight*this.view.scale/2)<1.1;});
 }
 draw(state:GridRenderState) {
  this.lastState=state;
  const c=this.ctx,w=this.width,h=this.height,night=this.world.model.level.chapter==='cave',time=this.settings.lowMotion?0:state.time;
  this.view=makeGridView(this.world.layout,w,h,state.player);const scale=this.view.scale;
  c.clearRect(0,0,w,h);c.fillStyle=night?'#253047':'#d1d2b5';c.fillRect(0,0,w,h);
  const bg=this.images.get('background');
  if(bg?.complete&&bg.naturalWidth){const factor=Math.max(w/bg.naturalWidth,h/bg.naturalHeight);const bw=bg.naturalWidth*factor,bh=bg.naturalHeight*factor;c.drawImage(bg,(w-bw)/2,(h-bh)/2,bw,bh);}
  c.fillStyle=night?'#1d2d5060':'#dce2c72c';c.fillRect(0,0,w,h);
  const haze=c.createLinearGradient(0,0,0,h);haze.addColorStop(0,night?'#1c284740':'#fff0c53b');haze.addColorStop(.7,'#f9eed500');haze.addColorStop(1,night?'#1421378c':'#dce5d45c');c.fillStyle=haze;c.fillRect(0,0,w,h);
  // Gaps are real absent tiles. Locked spans never render a traversable floor.
  const tiles=[...this.world.layout.tiles.values()].filter(t=>!t.gap&&this.world.tileVisible(t)&&this.world.ownerOpen(t)).sort((a,b)=>(a.x+a.z)-(b.x+b.z));
  for(const tile of tiles)this.floor(tile);
  if(state.target&&this.world.tileOpen(state.target))this.tileOutline(this.world.layout.tiles.get(gridKey(state.target))!,'#fff2ab',2);
  const here=this.world.layout.tiles.get(gridKey(this.world.position));if(here)this.tileOutline(here,night?'#b8e8d398':'#fff4c282',1.3);
  const objects:{depth:number;draw:()=>void}[]=[];
  for(const tile of tiles){
   const p=projectTile(tile,this.view);
   if(tile.prop)objects.push({depth:tile.x+tile.z+.05,draw:()=>this.picture(tile.prop!,p.x,p.y+10*scale,(tile.prop==='arch'?175:tile.prop==='rock'?77:72)*scale)});
   if(!tile.solid&&!tile.room&&(tile.x*13+tile.z*7)%17===0)objects.push({depth:tile.x+tile.z+.1,draw:()=>this.picture('flowers',p.x+18*scale,p.y+4*scale,33*scale)});
  }
  const model=this.world.model;
  for(const node of model.level.nodes){
   if(!model.isVisible(node.id))continue;
   const point=this.world.layout.nodes[node.id],p=projectTile(point,this.view),active=model.isActive(node.id);
   objects.push({depth:point.x+point.z+.25,draw:()=>{
    if(node.id===model.level.exit)this.picture(model.state.completed?'bloom':'flower',p.x,p.y+10*scale,110*scale);
    else if(node.mechanism){const keys:Record<string,string>={grow:active?'bloom':'soil',vine:active?'bridge':'vine',lily:'lily-open',rhythm:'lilypad',reflect:'lily-open',light:active?'light':'moss',friend:active?'bloom':'soil',sequence:active?'light':'moss',switch:'crystal',water:'soil'};this.picture(keys[node.mechanism],p.x,p.y+8*scale,91*scale);}
    if(model.level.beam?.[1]===node.id)this.picture('crystal',p.x,p.y+8*scale,95*scale);
    if(node.spore&&!model.state.collected.includes(node.id))this.picture('fx:spore',p.x,p.y-35*scale+Math.sin(time/450+point.x)*3*scale,34*scale,.5);
    if(active&&this.settings.dynamicLight)this.picture('fx:glow',p.x,p.y,120*scale,.6,.23);
    if(state.hint===node.id)this.tileOutline(point,'#fff3a9',3);
    if(model.level.sequence&&state.time<state.clueUntil&&model.level.sequence[Math.floor((6500-(state.clueUntil-state.time))/1300)]===node.id){this.tileOutline(point,'#fff3a9',5);this.picture('fx:glow',p.x,p.y,150*scale,.7,.6);}
   }});
  }
  const actorPoint=projectTile(state.player,this.view),lift=state.travel?.jump?jumpHeight(state.travel.progress,this.settings.lowMotion)*scale:0;
  objects.push({depth:state.player.x+state.player.z+.4,draw:()=>{
   c.save();c.fillStyle='#243327';c.globalAlpha=.24-lift/600;c.beginPath();c.ellipse(actorPoint.x,actorPoint.y+7*scale,21*scale-lift*.04,8*scale,0,0,Math.PI*2);c.fill();c.restore();
   if(state.travel&&!this.settings.lowMotion&&this.settings.particles)this.picture('fx:trail',actorPoint.x-12*scale,actorPoint.y+8*scale,76*scale,.7,.35);
   const pose=state.pose;const image=this.images.get(`actor:${pose.key}`)??this.images.get('actor:idle-front');
   if(image?.complete&&image.naturalWidth){const size=126*scale;c.save();c.translate(actorPoint.x,actorPoint.y+8*scale-lift+pose.offsetY*scale);
    if(pose.clip==='roll'){c.translate(0,-31*scale);c.rotate(pose.rotation);c.scale(pose.scaleX,pose.scaleY);c.drawImage(image,-size/2,-size*.58,size,size);}
    else{c.rotate(pose.rotation);c.scale(pose.flip?-pose.scaleX:pose.scaleX,pose.scaleY);c.drawImage(image,-size/2,-size*236/256,size,size);}c.restore();}
   if(state.actionElapsed!==undefined&&state.actionElapsed<900&&this.settings.dynamicLight)this.picture('fx:growth',actorPoint.x,actorPoint.y+20*scale,140*scale,.8,.5*Math.sin(state.actionElapsed/900*Math.PI));
  }});
  objects.sort((a,b)=>a.depth-b.depth).forEach(o=>o.draw());
  if(model.level.companion){const point=this.world.layout.nodes[model.state.buddy],p=projectTile(point,this.view);this.picture('bug',p.x+26*scale+Math.sin(time/600)*8,p.y-20*scale,70*scale);}
  if(model.level.beam){const path=model.beamPath();c.save();c.strokeStyle='#fff0ad';c.shadowColor='#ffdb7b';c.shadowBlur=12;c.lineWidth=3*scale;c.beginPath();path.forEach((id,i)=>{const p=projectTile(this.world.layout.nodes[id],this.view);if(i)c.lineTo(p.x,p.y-20*scale);else c.moveTo(p.x,p.y-20*scale);});c.stroke();c.restore();}
  if(this.settings.particles)for(let i=0;i<(this.settings.quality==='soft'?10:24);i++){const x=(i*137+Math.sin(time/4200+i)*14+w)%w,y=(i*79-time/85%h+h)%h;c.globalAlpha=.3+(Math.sin(time/700+i)+1)*.15;c.fillStyle='#fff3ba';c.beginPath();c.arc(x,y,1+i%2,0,Math.PI*2);c.fill();}c.globalAlpha=1;
 }
}
