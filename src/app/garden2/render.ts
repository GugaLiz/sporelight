import type {SaveData} from '../types';
import {smallLeaf} from '../game/creatureArt';
import {drawMushroomBuddy} from '../game/mushroomBuddy';
import {drawMole} from '../game/mole';
import {DIRECTION,type GardenState,type Point,type Tile} from './types';
import {GardenWorld} from './world';
import {gardenScenery,terrainSurface,GARDEN_SCENERY_ASSETS} from './scenery';
import {drawFountain,drawButterflies,drawLeafPlate,drawLever} from './gardenArt';
import {MoleConversation} from './moleDialogue';
import {drawBell,drawCarryBag} from './itemArt';
import {TERRAIN_RISE,faceDepth,terrainSteps,drawPond,drawTerrainSteps,drawRunoff,runoffSource,drawWetPaving,drawShallowStone,type LandscapeView} from './landscape';
import {CHARACTER_FILES,characterPose,facingFor,jumpHeight,type Facing} from '../game/characterMotion';
export interface Motion{from:GardenState;to:GardenState;progress:number;kind:string;startedAt:number;walkStartedAt:number;duration:number}
export class GardenRenderer{
 readonly c:CanvasRenderingContext2D;readonly images=new Map<string,HTMLImageElement>();width=1280;height=720;scale=1;ox=0;oy=0;overview=false;private lastSize='';
 private moleConversation=new MoleConversation();
 private luvieFacing:Facing='front';
 constructor(readonly canvas:HTMLCanvasElement,readonly world:GardenWorld,private settings:SaveData['settings']){
  this.c=canvas.getContext('2d')!;for(const key of ['stone','grass','stairs','arch','rock','flowers','crystal','lilypad'])this.load(key,`./images/grid-world/${key}.png`);
  for(const key of ['flower','bloom','vine','light','bug'])this.load(key,`./images/production/${key}.png`);
  for(const key of CHARACTER_FILES)this.load(key,`./images/material-ready/${key}.png`);
  for(const key of GARDEN_SCENERY_ASSETS)this.load(key,`./images/garden-scenery/${key}.png`);this.load('bush','./images/grid-world/bush.png');
  this.load('flower-gate-frame','./images/garden-scenery/flower-gate-frame.png');this.load('flower-gate-seal','./images/garden-scenery/flower-gate-seal.png');
  for(const key of ['paving-valley','paving-pond','paving-grass','paving-moss','valley-wall-left','valley-wall-right','masonry-valley','masonry-pond','water-pigment'])this.load(key,`./images/garden-scenery/${key}.jpg`);
  this.load('spore','./images/material-ready/icon-spore.png');this.load('wall-left','./images/grid-world/wall-left.jpg');this.load('wall-right','./images/grid-world/wall-right.jpg');
  this.load('ball','./images/journey-gardens/buddy-ball.png');this.load('background',world.level.chapter==='pond'?'./images/garden-scenery/pond-mist.jpg':`./images/grid-world/sky-${world.level.chapter}.jpg`);this.resize();
 }
 private load(key:string,url:string){const im=new Image();im.src=url;this.images.set(key,im);}
 private bell(x:number,y:number){const c=this.c,k=this.scale;drawBell(c,x,y,k);c.save();c.font='12px Microsoft YaHei';c.textAlign='center';c.fillStyle='#fff5dc';const lx=Math.max(48,Math.min(this.width-48,x));c.fillRect(lx-44,y-65*k,88,23);c.fillStyle='#87663c';c.fillText('门铃 · 拾起',lx,y-65*k+16);c.restore();}
 configure(s:SaveData['settings']){this.settings=s;this.resize();}
 resize(){this.width=this.canvas.clientWidth||1280;this.height=this.canvas.clientHeight||720;const d=this.settings.quality==='soft'?1:Math.min(devicePixelRatio||1,2),key=`${this.width}:${this.height}:${d}`;if(key!==this.lastSize){this.canvas.width=this.width*d;this.canvas.height=this.height*d;this.c.setTransform(d,0,0,d,0,0);this.lastSize=key;}}
 private raw(p:Point){return{x:(p.x-p.z)*35,y:(p.x+p.z)*17.5-p.h*TERRAIN_RISE};}
 project(p:Point){const q=this.raw(p);return{x:this.ox+q.x*this.scale,y:this.oy+q.y*this.scale};}
 private view(player:Point){
  const tiles=this.world.tiles,all=[...tiles,...this.world.level.modules.flatMap(m=>[{x:m.x+4,z:m.z+4,h:m.high??m.h},{x:m.x-4,z:m.z-4,h:m.h}])],p=all.map(p=>this.raw(p));
  const minX=Math.min(...p.map(t=>t.x))-65,maxX=Math.max(...p.map(t=>t.x))+65,minY=Math.min(...p.map(t=>t.y))-120,maxY=Math.max(...all.map(p=>this.raw({...p,h:0}).y))+(this.world.level.chapter==='valley'?145:125);
  if(this.width<650&&!this.overview){this.scale=.92;const q=this.raw(player);this.ox=this.width*.38-q.x*this.scale;this.oy=this.height*.5-q.y*this.scale;}
  else{this.scale=Math.min(this.world.level.chapter==='valley'?1.5:1.28,(this.width-(this.width<650?25:330))/(maxX-minX),(this.height-(this.width<650?310:185))/(maxY-minY));this.ox=this.width*(this.width<650?.5:.46)-(minX+maxX)/2*this.scale;this.oy=this.height*.52-(minY+maxY)/2*this.scale;}
 }
 private poly(points:number[][],fill:string|CanvasGradient,stroke?:string){const c=this.c;c.beginPath();points.forEach(([x,y],i)=>i?c.lineTo(x,y):c.moveTo(x,y));c.closePath();c.fillStyle=fill;c.fill();if(stroke){c.strokeStyle=stroke;c.lineWidth=.7;c.stroke();}}
 private image(key:string,x:number,y:number,w:number,anchor=.9,alpha=1){const im=this.images.get(key);if(!im?.complete||!im.naturalWidth)return;const h=w*im.naturalHeight/im.naturalWidth;this.c.save();this.c.globalAlpha*=alpha;this.c.drawImage(im,x-w/2,y-h*anchor,w,h);this.c.restore();}
 private line(points:Point[],color:string,width=2,dash=false){const c=this.c;c.save();c.strokeStyle=color;c.lineWidth=width*this.scale;c.lineCap='round';if(dash)c.setLineDash([5,6]);c.beginPath();points.forEach((p,i)=>{const q=this.project(p);if(i)c.lineTo(q.x,q.y);else c.moveTo(q.x,q.y);});c.stroke();c.restore();}
 private growthGuide(time:number,explicit:boolean){
  const g=this.world.growthGuidance();if(!g)return;const c=this.c,s=this.scale,grown=this.world.state.growth[g.root.id];
  const diamond=(point:Point,bright:boolean)=>{const p=this.project(point),w=29*s,h=14.5*s;c.save();c.globalAlpha=bright?(this.settings.lowMotion ? .75 :.58+Math.sin(time*.003)*.16):(this.settings.lowMotion?.32:.25+Math.sin(time*.002)*.07);if(bright&&this.settings.dynamicLight){c.shadowColor='#e9d479';c.shadowBlur=13*s;}this.poly([[p.x-w,p.y],[p.x,p.y-h],[p.x+w,p.y],[p.x,p.y+h]],bright?'#f6e6a33b':'#d5cda018',bright?'#f3d47e':'#9da876');c.restore();};
  for(const [x,z]of g.root.sockets)if(!grown.includes(`g:${g.root.id}:${x}:${z}`))diamond({x,z,h:g.root.h},explicit&&g.route[0]?.x===x&&g.route[0]?.z===z);
  diamond(g.origin,true);
  if(!explicit)return;
  const arrow=(a:Point,b:Point)=>{const p=this.project(a),q=this.project(b),dx=q.x-p.x,dy=q.y-p.y,length=Math.hypot(dx,dy);if(!length)return;const ux=dx/length,uy=dy/length;c.save();c.strokeStyle='#4f9787';c.lineWidth=Math.max(3,3.5*s);c.lineCap='round';c.beginPath();c.moveTo(p.x+ux*9*s,p.y+uy*9*s);c.lineTo(q.x-ux*9*s,q.y-uy*9*s);c.stroke();const ex=q.x-ux*7*s,ey=q.y-uy*7*s;this.poly([[ex,ey],[ex-ux*9*s-uy*4*s,ey-uy*9*s+ux*4*s],[ex-ux*9*s+uy*4*s,ey-uy*9*s-ux*4*s]],'#4f9787');c.restore();};
  let previous:Point=g.end;
  for(const [i,point]of g.route.entries()){arrow(previous,point);const p=this.project(point);c.save();c.font='bold 12px Microsoft YaHei';c.textAlign='center';c.fillStyle='#fff9e8';c.beginPath();c.arc(p.x+22*s,p.y-13*s,9,0,Math.PI*2);c.fill();c.fillStyle='#8c6c35';c.fillText(String(grown.length+i+1),p.x+22*s,p.y-13*s+4);c.restore();previous=point;}
  const goal=this.project({x:g.root.goal[0],z:g.root.goal[1],h:g.root.h});c.save();c.font='11px Microsoft YaHei';c.textAlign='center';const label=g.retract?'回根台调整根线':'第4节：接入花床',width=c.measureText(label).width+14;c.fillStyle='#fff8e7ee';c.fillRect(goal.x-width/2,goal.y+18*s,width,22);c.fillStyle='#8c6c35';c.fillText(label,goal.x,goal.y+18*s+15);c.restore();
  if(grown.length===g.root.budget-1&&!g.retract){const bx=goal.x-36,by=goal.y+50; c.save();c.strokeStyle='#529b88';c.lineWidth=2;c.setLineDash([4,3]);c.beginPath();c.moveTo(bx+36,by);c.lineTo(goal.x,goal.y+8*s);c.stroke();c.fillStyle='#f4fff4f5';c.fillRect(bx-20,by,112,24);c.fillStyle='#477d6a';c.font='bold 12px Microsoft YaHei';c.textAlign='center';c.fillText('还差第4节根芽',bx+36,by+16);c.restore();}
  if(!this.world.near(g.root.at)){const path=this.world.pathTo(g.root.at);if(path){let from=this.world.point;for(const id of path){const to=this.world.pointFor(id);this.line([from,to],'#bddbc0',3,true);from=to;}}}
 }
 private floor(t:Tile,tiles:Tile[],view:LandscapeView,alpha=1){
  const c=this.c,p=this.project(t),w=70*this.scale,h=35*this.scale,chapter=this.world.level.chapter,base=t.kind==='shadow'?11:t.kind==='root'?30:chapter==='valley'?112:chapter==='pond'?42:60;
  c.save();c.globalAlpha*=alpha;
  for(const side of ['left','right'] as const){
   const neighbor=tiles.find(n=>n.x===t.x+(side==='right'?1:0)&&n.z===t.z+(side==='left'?1:0)&&n.id!==t.id);
   const depth=faceDepth(t,neighbor,base)*this.scale;if(depth<.1)continue;
   const corners=side==='left'?[[p.x-w/2,p.y],[p.x,p.y+h/2],[p.x,p.y+h/2+depth],[p.x-w/2,p.y+depth]]:[[p.x,p.y+h/2],[p.x+w/2,p.y],[p.x+w/2,p.y+depth],[p.x,p.y+h/2+depth]];
   this.poly(corners,side==='left'?'#9b9b79':'#7c886f');
   const im=this.images.get(chapter==='cave'?`wall-${side}`:`masonry-${chapter}`);
   if(im?.complete&&im.naturalWidth){c.save();const u=(side==='left'?t.x:-t.z)*70,v=-t.h*TERRAIN_RISE;
    if(side==='left')c.transform(this.scale*.5,this.scale*.25,0,this.scale,p.x-w/2,p.y);else c.transform(this.scale*.5,-this.scale*.25,0,this.scale,p.x,p.y+h/2);
    c.translate(-u,-v);const pattern=c.createPattern(im,'repeat');if(pattern){c.fillStyle=pattern;c.fillRect(u,v,70,depth/this.scale);}c.restore();}
   const shade=c.createLinearGradient(0,p.y,0,p.y+depth);shade.addColorStop(0,chapter==='pond'?'#76a9a82a':'#b4b89415');shade.addColorStop(1,'#334d413a');this.poly(corners,shade);
   const seed=Math.abs(t.x*19+t.z*31+(side==='left'?3:0));
   if(chapter==='valley'&&seed%3===0&&depth>25*this.scale){c.save();this.poly(corners,'#ffffff00');c.clip();const vx=side==='left'?p.x-w*.28:p.x+w*.23,vy=p.y+h*.23,length=Math.min(depth*.75,85*this.scale);c.strokeStyle='#7b8962';c.lineWidth=1.1*this.scale;c.beginPath();c.moveTo(vx,vy);c.quadraticCurveTo(vx-5*this.scale,vy+length*.5,vx+2*this.scale,vy+length);c.stroke();const vine=this.images.get('trailing-vine');if(vine?.complete&&vine.naturalWidth){const width=Math.min(24*this.scale,length*vine.naturalWidth/vine.naturalHeight);c.drawImage(vine,vx-width/2,vy,width,length);}else for(let n=0;n<6;n++)smallLeaf(c,vx+Math.sin(n*2)*3*this.scale,vy+n*length/6,(.32+n%2*.14)*this.scale,n%2?.8:-.4);c.restore();}
  }
  const diamond=[[p.x,p.y-h/2],[p.x+w/2,p.y],[p.x,p.y+h/2],[p.x-w/2,p.y]];
  this.poly(diamond,chapter==='pond'?'#aec0af':'#cec8a4');
  const im=this.images.get(terrainSurface(this.world.level,t));
  if(im?.complete&&im.naturalWidth){c.save();c.transform(w/2/im.naturalWidth,h/2/im.naturalWidth,-w/2/im.naturalHeight,h/2/im.naturalHeight,p.x,p.y-h/2);c.drawImage(im,0,0);c.restore();}
  this.poly(diamond,'#ffffff00','#efe4c06b');
  if(chapter==='pond'){if(t.kind==='water')drawShallowStone(view,t);else drawWetPaving(view,t);}
  if(t.kind==='root')this.image('flowers',p.x,p.y+5*this.scale,w*.35,.8,.6);
  if(t.kind==='shadow')this.poly(diamond,this.world.state.mode?'#b8d6ed45':'#ffe1a045','#eee7ae');
  if(t.kind==='module')this.poly(diamond,'#d8d7b515','#e9e0b18a');
  c.restore();
 }
 draw(time:number,motion?:Motion,hint=false){
  this.resize();const c=this.c,w=this.width,h=this.height,t=this.settings.lowMotion?0:time;
  const bg=this.images.get('background');c.fillStyle='#d9dfcc';c.fillRect(0,0,w,h);if(bg?.complete&&bg.naturalWidth){const f=Math.max(w/bg.naturalWidth,h/bg.naturalHeight);c.drawImage(bg,(w-bg.naturalWidth*f)/2,(h-bg.naturalHeight*f)/2,bg.naturalWidth*f,bg.naturalHeight*f);}
  c.fillStyle=this.world.level.chapter==='cave'?'#14223944':'#f2ecd822';c.fillRect(0,0,w,h);
  const future=motion?new GardenWorld(this.world.level.id,motion.to):undefined;
  const a=this.world.tiles,b=future?.tiles??a,k=motion?motion.progress*motion.progress*(3-2*motion.progress):0;
  const travelProgress=motion&&['move','roll','rejoin'].includes(motion.kind)?motion.progress:k;
  const interpolate=(p:Point,q?:Point,progress=k):Point=>{
   if(!q)return p;const tile=p as Tile,m=tile.module?this.world.level.modules.find(m=>m.id===tile.module):undefined;
   if(m?.kind==='rotate'&&motion&&(q as Tile).id===tile.id){let delta=((motion.to.turns[m.id]??0)-(motion.from.turns[m.id]??0)+4)%4;if(delta>2)delta-=4;const angle=delta*Math.PI/2*k,dx=p.x-m.x,dz=p.z-m.z;return{x:m.x+dx*Math.cos(angle)-dz*Math.sin(angle),z:m.z+dx*Math.sin(angle)+dz*Math.cos(angle),h:p.h+(q.h-p.h)*k};}
   return{x:p.x+(q.x-p.x)*progress,z:p.z+(q.z-p.z)*progress,h:p.h+(q.h-p.h)*progress};
  };
  const current=this.world.point;let player:Point=current;
  if(motion&&future){const actor=this.world.actor;player=interpolate(this.world.pointFor(motion.from.actors[actor]),future.pointFor(motion.to.actors[actor]),travelProgress);}
  this.view(player);
  const landscape:LandscapeView={c,scale:this.scale,time:t,particles:this.settings.particles,project:p=>this.project(p),images:this.images};
  // Valve settings raise the hydraulic flower deck; the surrounding shallows stay below the fixed banks.
  const waterSetting=motion?motion.from.water+(motion.to.water-motion.from.water)*k:this.world.state.water;
  const waterHeight=this.world.level.id==='2-1'?-.55+waterSetting*.18:-.5;
  if(this.world.level.chapter==='pond')drawPond(landscape,this.world.level,a,waterHeight);
  const painted=a.filter(p=>this.world.visible(p)).map(p=>({...p,...interpolate(p,b.find(q=>q.id===p.id)),alpha:b.some(q=>q.id===p.id)?1:1-k}));
  if(motion)for(const p of b)if(!a.some(q=>q.id===p.id))painted.push({...p,alpha:k});
  const objects:{depth:number;draw:()=>void}[]=painted.map(p=>({depth:p.x+p.z,draw:()=>this.floor(p,painted,landscape,p.alpha)}));
  if(!motion||['move','roll','rejoin','jump','hop'].includes(motion.kind))for(const [low,high]of terrainSteps(a))objects.push({depth:Math.max(low.x+low.z,high.x+high.z)+.04,draw:()=>drawTerrainSteps(landscape,[low,high])});
  const runoff=runoffSource(this.world.level,a);if(runoff&&this.world.level.chapter!=='cave')objects.push({depth:runoff.x+runoff.z+.6,draw:()=>drawRunoff(landscape,this.world.level,painted,waterHeight)});
  const l=this.world.level,s=this.world.state;
  const surfaceLine=(points:Point[],color:string,width:number)=>{for(let n=1;n<points.length;n++){
   const a=points[n-1],b=points[n],count=Math.max(1,Math.ceil(Math.max(Math.abs(b.x-a.x),Math.abs(b.z-a.z))));
   for(let i=0;i<count;i++){const at=(f:number)=>({x:a.x+(b.x-a.x)*f,z:a.z+(b.z-a.z)*f,h:a.h+(b.h-a.h)*f}),p=at(i/count),q=at((i+1)/count);objects.push({depth:Math.max(p.x+p.z,q.x+q.z)+.06,draw:()=>this.line([p,q],color,width)});}
  }};
  // Channels use the same rotation as the platform, and visibly end at their consumers.
  for(const m of l.modules)if(m.id==='water'){
   const p=this.world.modulePoint(m.id,[0,0]);const turn=s.turns[m.id];
   const dirs=[[0,-1],[1,0],[0,1],[-1,0]];
   for(const n of [turn,(turn+1)%4]){const [dx,dz]=dirs[n];surfaceLine([p,{...p,x:p.x+dx*3,z:p.z+dz*3}],'#a2e3e4',4);}
  }
  if(l.id==='3-3'&&this.world.flag('root'))surfaceLine([{x:0,z:-4,h:0},{x:1,z:-4,h:0},{x:4,z:-3,h:0}],'#c4d79b',2);
  if(l.id==='3-4'&&s.turns.water===1)surfaceLine([{x:0,z:8,h:0},{x:4,z:8,h:0},{x:4,z:0,h:0}],'#b4e6e6',3);
  if(l.id==='3-4'&&s.turns.water===1&&s.turns.inner===1)surfaceLine([{x:4,z:0,h:0},{x:0,z:0,h:0},{x:0,z:-4,h:0}],'#b4e6e6',3);
  const rays=this.world.rays(),minX=Math.min(...a.map(p=>p.x))-1,maxX=Math.max(...a.map(p=>p.x))+1,minZ=Math.min(...a.map(p=>p.z))-1,maxZ=Math.max(...a.map(p=>p.z))+1;
  if(rays.length)surfaceLine(rays.filter(p=>p.x>=minX&&p.x<=maxX&&p.z>=minZ&&p.z<=maxZ),'#ffe4a1',3);
  const lampRay=this.world.lampRay();if(lampRay.length)surfaceLine(lampRay,'#ffeab181',4);
  const dialogue=this.canvas.closest('.garden-game')?.querySelector<HTMLElement>('#gardenMoleDialogue');if(dialogue)dialogue.hidden=true;
  if(l.id==='1-4'||l.id==='3-4'&&s.completed){const core=l.marks.find(m=>m.id==='home')??l.marks.find(m=>m.kind==='core')!,p=a.find(t=>t.id===core.tile)!;const q=this.project({...p,x:p.x-1,z:p.z+.3});
   const speech=l.id==='1-4'?this.moleConversation.update(s,this.world.near(core.tile),time):undefined;
   if(l.id==='1-4'){
    if(dialogue&&speech&&q.x>-35&&q.x<this.width+35&&q.y>100&&q.y<this.height-100){dialogue.hidden=false;if(dialogue.textContent!==speech)dialogue.textContent=speech;const width=Math.min(250,this.width-32);dialogue.style.width=width+'px';dialogue.style.left=Math.max(16,Math.min(this.width-width-16,q.x-width/2))+'px';dialogue.style.top=Math.max(160,Math.min(this.height-260,q.y+26*this.scale))+'px';}
   }
   objects.push({depth:p.x+p.z+.2,draw:()=>drawMole(c,q.x,q.y,58*this.scale,t,{greet:(this.world.flag('home')||s.completed)&&!!speech,speaking:!!speech,lowMotion:this.settings.lowMotion})});}

  for(const prop of gardenScenery(l)){if(!this.world.visible({...prop,id:''}))continue;const p=this.project(prop);objects.push({depth:prop.depth??prop.x+prop.z+.08,draw:()=>this.image(prop.asset,p.x,p.y+7*this.scale,prop.width*this.scale)});}
  if(l.sanctuary){
   const gate=l.sanctuary.gate,q=this.project(gate),f=this.project(l.sanctuary.fountain);
   const opening=s.flags.includes('home')?1:motion?.to.flags.includes('home')?k:0;
   objects.push({depth:gate.x+gate.z+.2,draw:()=>{
    this.image('flower-gate-frame',q.x,q.y+13*this.scale,112*this.scale,.93);
    c.save();c.translate(q.x,q.y+13*this.scale);c.scale(1-opening*.18,1);this.image('flower-gate-seal',0,0,112*this.scale,.93,1-opening);c.restore();
    if(this.settings.dynamicLight&&opening<1){c.save();const glow=c.createRadialGradient(q.x,q.y-55*this.scale,2,q.x,q.y-55*this.scale,40*this.scale);glow.addColorStop(0,`rgba(186,232,183,${.12*(1-opening)})`);glow.addColorStop(1,'#b0dcb000');c.fillStyle=glow;c.fillRect(q.x-45*this.scale,q.y-100*this.scale,90*this.scale,90*this.scale);c.restore();}
   }});
   objects.push({depth:l.sanctuary.fountain.x+l.sanctuary.fountain.z+.1,draw:()=>drawFountain(c,f.x,f.y,92*this.scale,t,this.settings.particles,this.images.get('stone'))});
   if(this.settings.particles){const flowers=gardenScenery(l).filter(prop=>prop.x<=-7&&['pink-flowers','blue-flowers','yellow-flowers','ivory-lotus','glow-flower','gold-lotus','flowers'].includes(prop.asset));const anchors=flowers.map(prop=>{const p=this.project(prop),image=this.images.get(prop.asset),height=prop.width*(image?.naturalWidth?image.naturalHeight/image.naturalWidth:1.3);return {x:(p.x-f.x)/this.scale,y:(p.y-f.y)/this.scale-height*.70};});objects.push({depth:1000,draw:()=>drawButterflies(c,f.x,f.y,this.scale,t,anchors)});}
  }
  for(const [x,z]of l.walls??[]){const q=this.project({x,z,h:0});objects.push({depth:x+z+.1,draw:()=>this.image('rock',q.x,q.y+5*this.scale,(l.id==='1-2'?38:70)*this.scale,.9,l.id==='1-2'?.65:1)});}
  for(const mark of l.marks){const p=a.find(t=>t.id===mark.tile);if(!p||!this.world.visible(p))continue;const q=this.project(interpolate(p,b.find(t=>t.id===p.id)));
   objects.push({depth:p.x+p.z+.1,draw:()=>{
    if(mark.kind==='core'){this.image(s.completed?'bloom':'flower',q.x,q.y+10*this.scale,(l.id==='3-4'?150:110)*this.scale);if(this.world.ready()&&this.settings.dynamicLight)this.image('light',q.x,q.y+5*this.scale,90*this.scale,.9,.22);}
    else if(mark.kind==='root')this.image('vine',q.x,q.y+8*this.scale,65*this.scale);
    else if(mark.kind==='latch')this.image('arch',q.x,q.y+8*this.scale,90*this.scale);
    else if(mark.kind==='flower')this.image(this.world.flag(mark.id)?'bloom':'flowers',q.x,q.y+8*this.scale,55*this.scale);
    else if(mark.kind==='lamp')this.image('light',q.x,q.y+8*this.scale,54*this.scale);
    else if(mark.id==='hold')drawLever(c,q.x+28*this.scale,q.y-8*this.scale,57*this.scale,this.world.flag('hold')?1:motion?.kind==='use:hold'?k:0,this.images.get('stone'));
    else if(mark.kind==='plate')drawLeafPlate(c,q.x,q.y,64*this.scale,s.actors.buddy===mark.tile,t,this.images.get('stone'),this.images.get('lilypad'));
    else if(mark.kind==='rest'||mark.kind==='observe')this.image('flowers',q.x,q.y+7*this.scale,34*this.scale);
    const caption=({core:'核心花床',root:'根台',turn:'转动庭院',valve:'花阀',lever:'操作杆',latch:'门闩',song:'雨滴琴',slot:'放置槽',plate:'轻叶踏板'} as Record<string,string>)[mark.kind];
    if(caption&&mark.id!=='hold'&&!s.completed&&this.world.near(mark.tile)){c.save();c.font='11px Microsoft YaHei';c.textAlign='center';const width=c.measureText(caption).width+14;c.fillStyle='#fff6e7e8';c.fillRect(q.x-width/2,q.y-49*this.scale,width,20);c.fillStyle='#7a6647';c.fillText(caption,q.x,q.y-49*this.scale+14);c.restore();}
   }});
  }
  for(const [id,item]of Object.entries(s.items)){
   const next=future?.state.items[id],ground=!item.holder&&item.tile?item:next&&!next.holder&&next.tile?next:undefined;
   if(!ground)continue;const p=a.find(t=>t.id===ground.tile)??b.find(t=>t.id===ground.tile);if(!p)continue;
   const q=this.project(interpolate(p,b.find(t=>t.id===p.id))),alpha=next?(item.holder?k:next.holder?1-k:1):1;
   objects.push({depth:p.x+p.z+.25,draw:()=>{c.save();c.globalAlpha*=alpha;
    if(id==='bug')this.image('bug',q.x,q.y-10*this.scale,40*this.scale);
    else if(id==='dew')this.image(ground.picked?'dew-parcel':'dew-plant',q.x,q.y+5*this.scale,ground.picked?34*this.scale:49*this.scale,1);
    else if(id.startsWith('mirror')){this.image('lilypad',q.x,q.y,52*this.scale);c.strokeStyle='#fff0b1';c.lineWidth=4*this.scale;c.beginPath();c.moveTo(q.x-12*this.scale,q.y+(ground.angle%2?7:-7)*this.scale);c.lineTo(q.x+12*this.scale,q.y+(ground.angle%2?-7:7)*this.scale);c.stroke();}
    else if(id==='bell')this.bell(q.x+18*this.scale,q.y);
    else this.image(id==='lamp'?'light':'crystal',q.x,q.y,36*this.scale);
    c.restore();
   }});
  }
  for(const col of l.collectibles)if(!s.collected.includes(col.id)){const p=a.find(t=>t.id===col.tile);if(!p||!this.world.visible(p))continue;const q=this.project(p);objects.push({depth:p.x+p.z+.3,draw:()=>this.image('spore',q.x-(s.items.bell?.tile===col.tile?18*this.scale:0),q.y-20*this.scale+Math.sin(t*.003)*2,35*this.scale,.5)});}
  for(const actor of ['buddy','luvie'] as const){const before=a.find(t=>t.id===s.actors[actor])!;let p:Point=before;if(motion&&future)p=interpolate(before,future.pointFor(future.state.actors[actor]),travelProgress);const q=this.project(p),offset=s.actors.luvie===s.actors.buddy?(actor==='buddy'?-24:8)*this.scale:0;objects.push({depth:p.x+p.z+.5+(actor==='luvie'?.01:0),draw:()=>{
   const moving=!!motion&&!!future&&motion.from.actors[actor]!==motion.to.actors[actor],action=motion&&s.active===actor&&!moving?motion.kind:undefined;
   const held=Object.entries(s.items).find(([,i])=>i.holder===actor),incoming=Object.entries(future?.state.items??{}).find(([,i])=>i.holder===actor),carried=held??incoming;
   const carryAlpha=held?(future&&!incoming?1-k:1):k;
   const carry=(buddy=false,rolling=false,pose='idle-front')=>{if(!carried)return;c.save();c.globalAlpha*=carryAlpha;drawCarryBag(c,carried[0],this.scale,this.images,buddy,rolling,pose);c.restore();};
   const jump=motion&&['jump','hop'].includes(motion.kind)&&s.active===actor?jumpHeight(motion.progress,this.settings.lowMotion)*this.scale:0;
   if(actor==='buddy'){drawMushroomBuddy(c,q.x+offset,q.y+4*this.scale-jump,46*this.scale,t,{moving,rolling:moving&&motion?.kind==='roll',waiting:!s.follow&&s.active!=='buddy',ball:this.images.get('ball'),lowMotion:this.settings.lowMotion,happy:s.completed});c.save();c.translate(q.x+offset,q.y+4*this.scale-jump);carry(true);c.restore();}
   else{
    const to=future?.pointFor(future.state.actors[actor])??before,fromScreen=this.raw(before),toScreen=this.raw(to);
    if(moving)this.luvieFacing=facingFor(toScreen.x-fromScreen.x,toScreen.y-fromScreen.y);
    const pose=characterPose({time:t,facing:this.luvieFacing,lowMotion:this.settings.lowMotion,complete:s.completed&&!moving&&!['jump','hop'].includes(motion?.kind??''),travel:moving?{progress:motion!.progress,startedAt:motion!.walkStartedAt,jump:motion?.kind==='hop',rolling:motion?.kind==='roll',distance:45}:motion&&['jump','hop'].includes(motion.kind)&&s.active===actor?{progress:motion.progress,startedAt:motion.startedAt,jump:true,rolling:false,distance:0}:null,action:action&&(action==='repair'||action.startsWith('grow:')||action==='use:plant')?{kind:'sow',startedAt:motion!.startedAt}:action&&(action.startsWith('take:')||action.startsWith('drop:')||action.startsWith('use:'))?{kind:'interact',startedAt:motion!.startedAt}:undefined});
    const idleLook=!moving&&!action&&s.active==='buddy'&&!this.settings.lowMotion;
    const key=idleLook?(Math.floor(t/3600)%3===1?'idle-side':Math.floor(t/3600)%3===2?'lean':'idle-front'):pose.key;
    this.canvas.dataset.characterClip=pose.clip;this.canvas.dataset.characterFrame=key;this.canvas.dataset.characterFacing=this.luvieFacing;
    this.canvas.dataset.characterX=String(q.x+offset);this.canvas.dataset.characterY=String(q.y+7*this.scale-jump);
    c.save();c.translate(q.x+offset,q.y+7*this.scale-jump);if(pose.clip!=='roll')c.rotate(pose.rotation);c.scale(pose.flip?-pose.scaleX:pose.scaleX,pose.scaleY);if(pose.clip==='roll'){c.translate(0,-30*this.scale);c.rotate(pose.rotation);this.image('ball',0,0,68*this.scale,.5);carry(false,true);}else{c.translate(0,pose.offsetY*this.scale);this.image(key,0,0,115*this.scale,236/256);carry(false,false,key);}c.restore();
    this.canvas.dataset.carriedItem=carried?.[0]??'';this.canvas.dataset.carryStyle=carried?'satchel':'';
   }
   if(s.active===actor&&!s.completed){c.save();c.strokeStyle='#fff0b7';c.lineWidth=2;c.beginPath();c.ellipse(q.x+offset,q.y+4*this.scale,24*this.scale,10*this.scale,0,0,Math.PI*2);c.stroke();c.restore();}
  }});}
  objects.sort((a,b)=>a.depth-b.depth).forEach(o=>o.draw());
  if(l.id==='1-2'&&!s.completed)this.growthGuide(t,hint);
  const commands=this.world.commands();for(const cmd of commands)if(cmd.target){const r=this.world.level.roots[0],match=/:(-?\d+):(-?\d+)$/.exec(cmd.target)!;const p=this.project({x:+match[1],z:+match[2],h:r.h});c.save();c.strokeStyle='#e7ca80';c.lineWidth=2;c.setLineDash([4,4]);c.beginPath();c.moveTo(p.x-25*this.scale,p.y);c.lineTo(p.x,p.y-13*this.scale);c.lineTo(p.x+25*this.scale,p.y);c.lineTo(p.x,p.y+13*this.scale);c.closePath();c.stroke();c.restore();}
  if(hint&&l.id!=='1-2'){const p=this.project(current);c.save();c.strokeStyle='#fff3a4';c.lineWidth=2;c.beginPath();c.ellipse(p.x,p.y,40*this.scale,20*this.scale,0,0,Math.PI*2);c.stroke();c.restore();}
  if(s.completed&&this.settings.particles)for(let i=0;i<16;i++){c.fillStyle='#ffedaf88';c.beginPath();c.arc((i*173+Math.sin(t*.001+i)*15)%w,(h+i*91-t*.02)%h,2,0,Math.PI*2);c.fill();}
 }
}
