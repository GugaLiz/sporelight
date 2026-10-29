import { GridWorld } from './GridWorld';
import { makeGridView, projectTile, gridKey, GRID_DIRECTIONS, type GridPoint, type GridPosition, type GridView, type GridTile } from './gridLayout';
import { CHARACTER_FILES, jumpHeight, type CharacterPose } from './characterMotion';
import type { SaveData } from '../types';
import type { RunState } from './model';
import { drawMushroomBuddy } from './mushroomBuddy';
import { drawLevelPresentation } from './levelPresentation';
import { drawMole } from './mole';
import { WorldFeedback } from './worldFeedback';
import { smallLeaf, oval, softMaterial } from './creatureArt';

export interface GardenTransition {progress:number;kind:'lift'|'bridge'|'companion';from:RunState;to:RunState;fromPoint:GridPoint;toPoint:GridPoint}

export interface GridRenderState {
 time:number;player:GridPoint;pose:CharacterPose;travel?:{progress:number;jump:boolean;from:GridPoint;to:GridPoint}|null;
 hint?:string;target?:GridPosition|null;clueUntil:number;actionElapsed?:number;structure?:GardenTransition;preview?:string;celebration?:number;
}
export class GridRenderer {
 readonly ctx:CanvasRenderingContext2D;
 readonly images=new Map<string,HTMLImageElement>();
 view:GridView;
 private width=1280;private height=720;
 private settings:SaveData['settings'];
 private lastState?:GridRenderState;
 private transitionCache?:{motion:GardenTransition;world:GridWorld};
 private feedback=new WorldFeedback();
 private counter={x:90,y:210};
 constructor(private canvas:HTMLCanvasElement,readonly world:GridWorld,settings:SaveData['settings']) {
  this.ctx=canvas.getContext('2d')!;this.settings=settings;
  const load=(key:string,url:string)=>{const im=new Image();im.src=url;this.images.set(key,im);};
  for(const key of ['grass','stone','cliff','moss-stone','stairs','rock','lantern','flowers','bush','lilypad','crystal','bridge','arch'])load(key,`./images/grid-world/${key}.png`);
  for(const key of ['wall-left','wall-right'])load(key,`./images/grid-world/${key}.jpg`);
  for(const key of ['soil','flower','bloom','moss','light','vine','lily','lily-open','bug','puddle'])load(key,`./images/production/${key}.png`);
  for(const key of CHARACTER_FILES)load(`actor:${key}`,`./images/material-ready/${key}.png`);
  for(const key of ['spore','trail','growth','glow'])load(`fx:${key}`,`./images/material-ready/fx-${key}.png`);
  load('background',`./images/grid-world/sky-${world.model.level.chapter}.jpg`);
  load('garden:ball','./images/journey-gardens/buddy-ball.png');
  this.view=makeGridView(world.layout,1280,720,world.point);this.configure(settings);
 }
 configure(settings:SaveData['settings']) {
  this.settings=settings;this.width=this.canvas.clientWidth||1280;this.height=this.canvas.clientHeight||720;
  const ratio=settings.quality==='hd'?Math.min(devicePixelRatio||1,2):settings.quality==='soft'?.8:1;
  const pixelWidth=Math.round(this.width*ratio),pixelHeight=Math.round(this.height*ratio);
  const resized=this.canvas.width!==pixelWidth||this.canvas.height!==pixelHeight;
  if(resized){this.canvas.width=pixelWidth;this.canvas.height=pixelHeight;}
  this.ctx.setTransform(ratio,0,0,ratio,0,0);
  const counter=document.getElementById('sporeCount')?.getBoundingClientRect(),rect=this.canvas.getBoundingClientRect();
  if(counter&&rect.width&&rect.height)this.counter={x:(counter.left+counter.width/2-rect.left)*this.width/rect.width,y:(counter.top+counter.height/2-rect.top)*this.height/rect.height};
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
  const model=this.world.model;
  if(!tile.room&&tile.edges.some(i=>{const e=model.level.edges[i];return !!(e.when||e.gate||e.beam)&&model.edgeOpen(e.from,e.to);})){
   const shadow=model.level.id==='3-2',color=shadow?(model.state.vars.dial==='moon'?'#b5c9e23d':'#f9dc9d35'):'#a9c58629';
   this.polygon([[p.x,p.y-h*.46],[p.x+w*.46,p.y],[p.x,p.y+h*.46],[p.x-w*.46,p.y]],color);
   if(shadow){c.save();c.strokeStyle=model.state.vars.dial==='moon'?'#d1e4ed9c':'#ffe7b28c';c.lineWidth=1; c.beginPath();c.moveTo(p.x-w*.38,p.y);c.lineTo(p.x,p.y+h*.38);c.lineTo(p.x+w*.38,p.y);c.stroke();c.restore();}
   else if((tile.x+tile.z)%2===0){c.save();c.translate(p.x+w*.28,p.y);c.scale(v.scale,v.scale);smallLeaf(c,0,0,.55,.5);c.restore();}
  }
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
  this.feedback.update(this.world.model.state,state.time);
  this.view=makeGridView(this.world.layout,w,h,state.player);const scale=this.view.scale;
  c.clearRect(0,0,w,h);c.fillStyle=night?'#253047':'#d1d2b5';c.fillRect(0,0,w,h);
  const bg=this.images.get('background');
  if(bg?.complete&&bg.naturalWidth){const factor=Math.max(w/bg.naturalWidth,h/bg.naturalHeight);const bw=bg.naturalWidth*factor,bh=bg.naturalHeight*factor;c.drawImage(bg,(w-bw)/2,(h-bh)/2,bw,bh);}
  c.fillStyle=night?'#1d2d5060':'#dce2c72c';c.fillRect(0,0,w,h);
  const haze=c.createLinearGradient(0,0,0,h);haze.addColorStop(0,night?'#1c284740':'#fff0c53b');haze.addColorStop(.7,'#f9eed500');haze.addColorStop(1,night?'#1421378c':'#dce5d45c');c.fillStyle=haze;c.fillRect(0,0,w,h);
  if(night&&this.settings.dynamicLight){const model=this.world.model,lights=model.level.nodes.filter(n=>['light','sequence'].includes(n.mechanism??'')&&model.state.activated.includes(n.id)).length;c.fillStyle=`rgba(170,199,198,${Math.min(.14,lights*.03)})`;c.fillRect(0,0,w,h);}
  // Gaps are real absent tiles. Locked spans never render a traversable floor.
  const motion=state.structure;
  if(motion&&this.transitionCache?.motion!==motion)this.transitionCache={motion,world:new GridWorld(this.world.model.level,motion.to)};
  if(!motion)this.transitionCache=undefined;
  const future=this.transitionCache?.world;
  const visual=(point:GridPoint,room?:string)=>motion?.kind==='lift'&&room===this.world.model.level.lift?.node?{...point,h:motion.fromPoint.h+(motion.toPoint.h-motion.fromPoint.h)*motion.progress}:point;
  const tiles=[...this.world.layout.tiles.values()].filter(t=>!t.gap&&this.world.tileVisible(t)&&this.world.ownerOpen(t)).map(t=>({...t,...visual(t,t.room)})).sort((a,b)=>(a.x+a.z)-(b.x+b.z));
  for(const tile of tiles){c.save();if(motion&&future&&!future.ownerOpen(tile))c.globalAlpha=1-motion.progress;this.floor(tile);c.restore();}
  if(motion&&future)for(const tile of future.layout.tiles.values())if(!tile.gap&&future.tileVisible(tile)&&future.ownerOpen(tile)&&!this.world.ownerOpen(tile)){c.save();c.globalAlpha=motion.progress;this.floor(tile);c.restore();}
  if(state.target&&this.world.tileOpen(state.target))this.tileOutline(this.world.layout.tiles.get(gridKey(state.target))!,'#fff2ab',2);
  const here=this.world.layout.tiles.get(gridKey(this.world.position));if(here)this.tileOutline(here,night?'#b8e8d398':'#fff4c282',1.3);
  const objects:{depth:number;draw:()=>void}[]=[];
  for(const tile of tiles){
   const p=projectTile(tile,this.view);
   if(tile.prop)objects.push({depth:tile.x+tile.z+.05,draw:()=>this.picture(tile.prop!,p.x,p.y+10*scale,(tile.prop==='arch'?175:tile.prop==='rock'?77:72)*scale)});
   if(!tile.solid&&!tile.room&&(tile.x*13+tile.z*7)%17===0)objects.push({depth:tile.x+tile.z+.1,draw:()=>this.picture('flowers',p.x+18*scale,p.y+4*scale,33*scale)});
  }
  const model=this.world.model;
  drawLevelPresentation(c,model,id=>projectTile(visual(this.world.layout.nodes[id],id),this.view),{time:state.time,scale,particles:this.settings.particles,dynamicLight:this.settings.dynamicLight,lowMotion:this.settings.lowMotion,picture:(...args)=>this.picture(...args)});
  for(const node of model.level.nodes){
   if(!model.isVisible(node.id))continue;
   const point=visual(this.world.layout.nodes[node.id],node.id),p=projectTile(point,this.view),active=model.isActive(node.id);
   objects.push({depth:point.x+point.z+.25,draw:()=>{
    if(node.id===model.level.exit){
     const finale=model.level.id==='3-4',size=(finale?150:110)*scale,breathe=this.settings.lowMotion?0:Math.sin(time/900)*1.5*scale;
     this.picture(model.state.completed?'bloom':'flower',p.x,p.y+10*scale+breathe,size);
     if(finale||model.level.id==='2-4'){const total=finale?4:3,count=finale?model.level.sequence!.filter(id=>model.state.activated.includes(id)).length:model.state.activated.includes('bell')?3:model.state.vars.lotus==='high'?2:model.state.activated.includes('reed')?1:0;c.save();
      for(let i=count;i<total;i++){c.strokeStyle=i%2?'#91a17c':'#617d60';c.lineWidth=(4-i*.3)*scale;c.beginPath();c.ellipse(p.x,p.y-(27+i*12)*scale,(31+i*3)*scale,9*scale,-.2+i*.12,0,Math.PI*2);c.stroke();smallLeaf(c,p.x+(i%2?1:-1)*(27+i*3)*scale,p.y-(27+i*12)*scale,.65*scale,i*.7);}
      c.restore();
     }
    }
    else if(node.mechanism){
     if(node.mechanism==='lift'){
      c.save();c.fillStyle='#b5c991bb';c.beginPath();c.ellipse(p.x,p.y,43*scale,20*scale,0,0,Math.PI*2);c.fill();this.picture('lily-open',p.x,p.y+9*scale,90*scale);
      c.fillStyle='#fff2c0';c.font=`${23*scale}px Georgia`;c.textAlign='center';c.fillText('↕',p.x,p.y-34*scale);c.restore();
     }else if(node.mechanism==='friend'&&model.level.coop){c.save();c.translate(p.x,p.y);c.scale(scale,scale);c.fillStyle=softMaterial(c,-9,-8,42,'#d5dda8',model.state.buddy==='wait'?'#b0c68b':'#92aa79','#647d55');c.beginPath();c.ellipse(0,0,29,15,-.18,0,Math.PI*2);c.fill();c.strokeStyle='#edf1c3a6';c.lineWidth=1.2;c.beginPath();c.moveTo(-23,6);c.quadraticCurveTo(0,-2,24,-6);c.stroke();for(let i=-1;i<=1;i++){c.beginPath();c.moveTo(i*12, -i*3);c.lineTo(i*12+5,-10);c.moveTo(i*12,-i*3);c.lineTo(i*12+8,8);c.stroke();}c.restore();}
     else if(node.mechanism==='latch'){this.picture('arch',p.x,p.y+9*scale,105*scale, .9,active?.68:1);c.save();c.fillStyle=active?'#f2d992':'#d8a773';c.font=`${19*scale}px Georgia`;c.textAlign='center';c.fillText(active?'✓':'⌘',p.x,p.y-40*scale);c.restore();}
     else {const keys:Record<string,string>={grow:active?'bloom':'soil',vine:'vine',lily:'lily-open',rhythm:'lilypad',reflect:'lily-open',light:active?'light':'moss',friend:active?'bloom':'soil',sequence:active?'light':'moss',switch:'crystal',water:'soil'};
      const emergence=this.settings.lowMotion?1:this.feedback.emergence(node.id,state.time);
      const growing=motion&&motion.to.activated.includes(node.id)&&!motion.from.activated.includes(node.id)&&node.mechanism==='grow';
      if(growing){this.picture('soil',p.x,p.y+8*scale,91*scale);this.picture('bloom',p.x,p.y+8*scale,(25+40*motion.progress)*scale,.9,motion.progress);}
      else this.picture(keys[node.mechanism],p.x,p.y+8*scale,91*scale*(active?.72+.28*emergence:1));
      if(node.mechanism==='reflect'&&model.state.vars[node.id]){const target=projectTile(this.world.layout.nodes[model.state.vars[node.id]],this.view),a=Math.atan2(target.y-p.y,target.x-p.x);c.save();c.translate(p.x,p.y-33*scale);c.rotate(a);c.strokeStyle='#fff0b8';c.lineWidth=1.7*scale;c.beginPath();c.moveTo(-12*scale,0);c.lineTo(17*scale,0);c.lineTo(11*scale,-4*scale);c.moveTo(17*scale,0);c.lineTo(11*scale,4*scale);c.stroke();c.restore();}
     }
    }
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
  const buddyPoint=model.level.coop&&model.state.buddy==='wait'?this.world.layout.nodes[model.level.coop.pad]:{...state.player,x:state.player.x-.45,z:state.player.z+.65};
  const buddyScreen=projectTile(buddyPoint,this.view);
  objects.push({depth:buddyPoint.x+buddyPoint.z+.45,draw:()=>drawMushroomBuddy(c,buddyScreen.x,buddyScreen.y+6*scale-(model.state.buddy==='wait'?0:lift*.72),53*scale,time,{rolling:state.pose.clip==='roll'&&model.state.buddy!=='wait',moving:!!state.travel&&model.state.buddy!=='wait',waiting:model.state.buddy==='wait',lowMotion:this.settings.lowMotion,ball:this.images.get('garden:ball'),happy:model.state.completed})});
  if(model.level.id==='1-4'){
   const from=this.world.layout.nodes.home,to=this.world.layout.nodes.garden,open=model.state.activated.includes('garden');
   const following=motion?.kind==='companion'&&!motion.from.activated.includes('garden')&&motion.to.activated.includes('garden');
   const q=following?motion.progress:open?1:0,m={x:from.x+(to.x-from.x)*q+.6,z:from.z+(to.z-from.z)*q+.15,h:from.h+(to.h-from.h)*q},p=projectTile(m,this.view);
   objects.push({depth:m.x+m.z+.5,draw:()=>drawMole(c,p.x,p.y+5*scale,64*scale,time,{greet:open,lowMotion:this.settings.lowMotion})});
  }
  if(model.level.id==='3-4'&&model.state.completed){const m={...this.world.layout.nodes.end,x:this.world.layout.nodes.end.x+1,z:this.world.layout.nodes.end.z+.6},p=projectTile(m,this.view);objects.push({depth:m.x+m.z+.5,draw:()=>drawMole(c,p.x,p.y+5*scale,53*scale,time,{greet:true,lowMotion:this.settings.lowMotion})});}
  objects.sort((a,b)=>a.depth-b.depth).forEach(o=>o.draw());
  if(model.level.coop&&model.state.activated.includes(model.level.coop.latch)){const p=projectTile(this.world.layout.nodes[model.level.coop.latch],this.view);this.picture('bug',p.x+28*scale,p.y-24*scale+Math.sin(time/700)*3*scale,33*scale,.8,.8);}
  if(state.preview){const edgeIndex=model.level.edges.findIndex(e=>(e.from===model.state.node&&e.to===state.preview)||(e.to===model.state.node&&e.from===state.preview));const path=this.world.layout.paths[edgeIndex];if(path?.length){c.save();c.strokeStyle='#f8e9af';c.lineWidth=3*scale;c.setLineDash([6*scale,6*scale]);c.beginPath();path.forEach((position,i)=>{const point=this.world.layout.tiles.get(gridKey(position));if(!point)return;const p=projectTile(point,this.view);if(i)c.lineTo(p.x,p.y);else c.moveTo(p.x,p.y);});c.stroke();c.restore();}}
  if(model.level.beam){const path=model.beamPath();c.save();c.strokeStyle='#fff0ad';c.shadowColor='#ffdb7b';c.shadowBlur=12;c.lineWidth=3*scale;c.beginPath();path.forEach((id,i)=>{const p=projectTile(this.world.layout.nodes[id],this.view);if(i)c.lineTo(p.x,p.y-20*scale);else c.moveTo(p.x,p.y-20*scale);});c.stroke();c.restore();}
  if(this.settings.particles)for(let i=0;i<(this.settings.quality==='soft'?10:24);i++){const x=(i*137+Math.sin(time/4200+i)*14+w)%w,y=(i*79-time/85%h+h)%h;c.globalAlpha=.3+(Math.sin(time/700+i)+1)*.15;c.fillStyle='#fff3ba';c.beginPath();c.arc(x,y,1+i%2,0,Math.PI*2);c.fill();}c.globalAlpha=1;
  this.feedback.draw(c,state.time,id=>model.isVisible(id)&&this.world.layout.nodes[id]?projectTile(visual(this.world.layout.nodes[id],id),this.view):undefined,this.counter,scale,this.settings);
  if(state.celebration!==undefined&&!this.settings.lowMotion){
   const p=projectTile(this.world.layout.nodes[model.level.exit],this.view),q=Math.min(1,state.celebration/(model.level.id==='3-4'?3000:1200));
   if(this.settings.dynamicLight){const g=c.createRadialGradient(p.x,p.y-40*scale,0,p.x,p.y-40*scale,(100+q*350)*scale);g.addColorStop(0,`rgba(255,237,183,${(1-q)*.25})`);g.addColorStop(1,'#ffeeb700');c.fillStyle=g;c.fillRect(0,0,w,h);}
   if(this.settings.particles)for(let i=0;i<(model.level.id==='3-4'?36:14);i++){const a=i*2.399,r=(30+q*140)*scale,x=p.x+Math.cos(a)*r,y=p.y-25*scale-q*90*scale+Math.sin(a)*r*.45;c.save();c.globalAlpha=Math.sin(q*Math.PI)*.8;oval(c,x,y,(2+i%3)*scale,(1+i%2)*scale,i%2?'#f1dbb3':'#d5e7b8',a+q);c.restore();}
  }
 }
}
