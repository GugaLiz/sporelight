import type {GardenWorld} from './world';
import type {Point} from './types';

export interface MirrorGuide{
 stage:'take'|'place'|'turn-a'|'turn-b'|'plant';tile:string;action:string;
 label:string;message:string;route:Point[];
}
/** Read the real mirrors after every move, undo and reload; no tutorial progress is saved. */
export function mirrorGuidance(world:GardenWorld):MirrorGuide|undefined{
 if(world.level.id!=='2-2'||world.state.completed)return;
 const {items}=world.state,a=items.mirrorA,b=items.mirrorB;
 const source=world.level.marks.find(m=>m.id==='source')!,slot=world.level.marks.find(m=>m.id==='slot')!,core=world.level.marks.find(m=>m.kind==='core')!;
 const route=[source.tile,a.tile,slot.tile,core.tile].map(id=>world.level.tiles.find(t=>t.id===id)!);
 const common={route};
 if(b.holder)return {...common,stage:'place',tile:slot.tile,action:`drop:mirrorB:${slot.tile}`,label:'把镜叶放到这里',message:'跟着箭头到发光的叶形槽，走近后点「放入镜叶」。'};
 if(b.tile!==slot.tile)return {...common,stage:'take',tile:b.tile,action:'take:mirrorB',label:'先搬这片镜叶',message:'先走近发光的反光叶，点「搬起镜叶」，再带到叶形光槽。'};
 if(a.angle%2!==1)return {...common,stage:'turn-a',tile:a.tile,action:'angle:mirrorA',label:'转动①，让光向上',message:'走近①号镜叶，点「转动镜叶」；让光从这里向上折向②。'};
 if(b.angle%2!==1)return {...common,stage:'turn-b',tile:b.tile,action:'angle:mirrorB',label:'转动②，让光向右',message:'走近②号镜叶，点「转动镜叶」；让光向右照到花床。'};
 return {...common,stage:'plant',tile:core.tile,action:'repair',label:'光已接通，去花床',message:'两片镜叶已经接通光路。和小苔灵到发光花床旁，一起种下微光。'};
}

interface GuideView{c:CanvasRenderingContext2D;scale:number;project:(p:Point)=>{x:number;y:number}}
/** Stable, legible rings and leaf-shaped floor socket; pulses are optional. */
export function drawMirrorSocket(v:GuideView,point:Point,occupied:boolean,time:number,lowMotion:boolean){
 const {c,scale:s}=v,p=v.project(point),pulse=lowMotion?1:.82+Math.sin(time*.003)*.18;
 c.save();c.translate(p.x,p.y);c.scale(s,s);c.globalAlpha=pulse;
 const g=c.createRadialGradient(0,0,2,0,0,37);g.addColorStop(0,occupied?'#e8d99455':'#b0ead77a');g.addColorStop(1,'#d2f4d900');c.fillStyle=g;c.fillRect(-38,-24,76,48);
 c.strokeStyle=occupied?'#e1cc81':'#c0efdf';c.lineWidth=2.2;c.setLineDash(occupied?[]:[4,3]);c.beginPath();c.ellipse(0,0,28,13,0,0,Math.PI*2);c.stroke();
 if(!occupied){c.setLineDash([]);c.fillStyle='#dcf7d737';c.beginPath();c.moveTo(-15,4);c.bezierCurveTo(-13,-11,11,-10,16,-4);c.bezierCurveTo(13,8,-4,10,-15,4);c.fill();c.stroke();c.lineWidth=1;c.beginPath();c.moveTo(-12,4);c.lineTo(12,-4);c.stroke();}
 c.restore();
}
export function drawMirrorFocus(v:GuideView,point:Point,time:number,lowMotion:boolean){
 const {c,scale:s}=v,p=v.project(point),pulse=lowMotion?1:.8+Math.sin(time*.003)*.2;
 c.save();c.globalAlpha=pulse;c.strokeStyle='#ffdc8a';c.lineWidth=2.3*s;c.beginPath();c.ellipse(p.x,p.y+2*s,29*s,14*s,0,0,Math.PI*2);c.stroke();
 c.strokeStyle='#fff6cf';c.lineWidth=2*s;const y=p.y-50*s-(lowMotion?0:Math.sin(time*.003)*3*s);c.beginPath();c.moveTo(p.x,y-10*s);c.lineTo(p.x,y+3*s);c.moveTo(p.x-5*s,y-2*s);c.lineTo(p.x,y+3*s);c.lineTo(p.x+5*s,y-2*s);c.stroke();c.restore();
}
export function drawMirrorArrow(v:GuideView,from:Point,to:Point){
 const {c,scale:s}=v,a=v.project(from),b=v.project(to),dx=b.x-a.x,dy=b.y-a.y,len=Math.hypot(dx,dy);if(len<10)return;
 const x=a.x+dx*.55,y=a.y+dy*.55,ux=dx/len,uy=dy/len;c.save();c.strokeStyle='#87d5c6';c.lineWidth=2*s;c.beginPath();c.moveTo(x-ux*7*s-uy*4*s,y-uy*7*s+ux*4*s);c.lineTo(x,y);c.lineTo(x-ux*7*s+uy*4*s,y-uy*7*s-ux*4*s);c.stroke();c.restore();
}
