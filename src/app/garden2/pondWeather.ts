import type {GardenLevel,Point,Tile} from './types';
import type {LandscapeView} from './landscape';
import {oval,softMaterial,glossyEye,smallLeaf} from '../game/creatureArt';

const fraction=(value:number)=>value-Math.floor(value);
export function rainDrop(index:number,time:number){
 const duration=2800+(index*137%1700),phase=fraction(time/duration+index*.61803398875);
 return {x:fraction(index*.754877666+.13),phase,length:5+index%9,near:index%5===0};
}
/** A whole drop/impact cycle stays on the same water point, including when paused. */
export function pondRainImpact(index:number,time:number){
 const phase=fraction(time/(3300+index%5*430)+index*.381966);
 return {phase,falling:phase<.64,height:phase<.64?(1-phase/.64)*105:0,radius:phase<.64?0:2+(phase-.64)/.36*19,alpha:phase<.64?.7:(1-phase)/.36};
}
export function drawRainAtmosphere(c:CanvasRenderingContext2D,width:number,height:number,time:number,foreground:boolean,lowMotion:boolean,particles:boolean){
 if(lowMotion||!particles)return;
 c.save();c.lineCap='round';
 const count=width<650?38:76;
 for(let i=0;i<count;i++){
  const drop=rainDrop(i,time);if(drop.near!==foreground)continue;
  const x=drop.x*width-drop.phase*12,y=drop.phase*(height+90)-45;
  c.strokeStyle=foreground?'#eefbf2a3':'#d7ecee52';c.lineWidth=foreground?1:.65;
  c.beginPath();c.moveTo(x,y);c.lineTo(x-1.5,y+drop.length*(foreground?1.6:1));c.stroke();
  if(foreground&&i%10===0){c.fillStyle='#d8f4ee5c';c.beginPath();c.moveTo(x,y+drop.length+1);c.bezierCurveTo(x-4,y+drop.length+7,x+3,y+drop.length+9,x,y+drop.length+1);c.fill();}
 }
 // Leaf-tip drips remain at the margin, clear of the interactive map.
 if(!foreground){c.restore();return;}
 for(const side of [-1,1])for(let i=0;i<3;i++){
  const phase=fraction(time/(5800+i*800)+i*.31),x=side<0?width*(.035+i*.04):width*(.965-i*.035),y=height*.1+phase*height*.8;
  if(phase>.7)continue;const size=1.1+i*.3;c.fillStyle='#d3f0ea96';c.beginPath();c.moveTo(x,y-5*size);c.bezierCurveTo(x-2*size,y,x-2*size,y+size,x,y+size);c.bezierCurveTo(x+2*size,y+size,x+2*size,y,x,y-5*size);c.fill();c.strokeStyle='#effff1a0';c.lineWidth=.6;c.stroke();
 }
 c.restore();
}

export function drawPondRain(v:LandscapeView,level:GardenLevel,tiles:Tile[],waterHeight:number,waterBounds:Point[]=level.tiles){
 if(!v.particles||v.lowMotion)return;
 const {c,scale:s,project,time}=v,minX=Math.min(...waterBounds.map(t=>t.x)),maxX=Math.max(...waterBounds.map(t=>t.x)),minZ=Math.min(...waterBounds.map(t=>t.z)),maxZ=Math.max(...waterBounds.map(t=>t.z));
 c.save();
 for(let i=0;i<23;i++){
  const x=minX+fraction(i*.75487766+.21)*(maxX-minX),z=minZ+fraction(i*.56984029+.37)*(maxZ-minZ);
  if(tiles.some(t=>Math.abs(t.x-x)+Math.abs(t.z-z)<1.3))continue;
  const p=project({x,z,h:waterHeight}),pose=pondRainImpact(i,time);c.globalAlpha=pose.alpha;
  if(pose.falling){c.strokeStyle='#edfdf2';c.lineWidth=1.1*s;c.beginPath();c.moveTo(p.x+2*s,p.y-pose.height*s-8*s);c.lineTo(p.x,p.y-pose.height*s);c.stroke();}
  else{
   c.strokeStyle='#e4f9ed';c.lineWidth=1*s;c.beginPath();c.ellipse(p.x,p.y,pose.radius*s,pose.radius*.32*s,0,0,Math.PI*2);c.stroke();
   c.globalAlpha*=.5;c.beginPath();c.ellipse(p.x,p.y,pose.radius*.62*s,pose.radius*.2*s,0,0,Math.PI*2);c.stroke();
   if(pose.phase<.79){c.globalAlpha=.8;const h=Math.sin((pose.phase-.64)/.15*Math.PI)*9*s;c.beginPath();c.moveTo(p.x-4*s,p.y);c.quadraticCurveTo(p.x,p.y-h*1.6,p.x+3*s,p.y);c.stroke();oval(c,p.x,p.y-h,1*s,1.5*s,'#f2fff2');}
  }
 }
 c.restore();
}

/** A few quiet residents sit on pads away from every moving platform's swept area. */
export function pondResidents(level:GardenLevel,tiles:Tile[]):Point[]{
 const minX=Math.min(...level.tiles.map(t=>t.x)),maxX=Math.max(...level.tiles.map(t=>t.x)),maxZ=Math.max(...level.tiles.map(t=>t.z));
 const candidates=[{x:minX-1.7,z:maxZ+.9,h:0},{x:maxX+1.6,z:maxZ+.8,h:0},{x:maxX-.7,z:maxZ+1.7,h:0}];
 return candidates.filter(p=>!tiles.some(t=>Math.abs(t.x-p.x)+Math.abs(t.z-p.z)<1.45)&&!level.modules.some(m=>Math.abs(p.z-m.z)<3&&p.x>=m.x-3&&p.x<=m.x+Math.abs(m.distance??0)+3)).slice(0,2);
}
export function drawPondResident(v:LandscapeView,point:Point,index:number){
 const {c,scale:s,project,time}=v,p=project(point);c.save();c.translate(p.x,p.y);c.scale(s,s);
 oval(c,0,2,22,8,'#467f7740');const pad=v.images.get('lilypad');if(pad?.complete&&pad.naturalWidth)c.drawImage(pad,-22,-9,44,21);
 const blink=time%6200>6010,bob=Math.sin(time/1600+index)*.35;
 c.translate(0,bob);oval(c,1,-9,10,7,softMaterial(c,-3,-13,14,'#d9e6a0','#9abb70','#5f8758'));oval(c,-6,-5,6,3,'#83a761');oval(c,7,-5,5,3,'#7e9e59');
 oval(c,-4,-15,6,5,softMaterial(c,-5,-18,9,'#e4ecb5','#a7c77a','#73965b'));oval(c,3,-15,5,5,'#adc97d');
 glossyEye(c,-5,-16,blink,.62);glossyEye(c,3,-16,blink,.62);c.strokeStyle='#6e8856';c.lineWidth=.7;c.beginPath();c.moveTo(-3,-10);c.quadraticCurveTo(0,-8,4,-10);c.stroke();
 smallLeaf(c,18,-1,.45,-.3);c.restore();
}
