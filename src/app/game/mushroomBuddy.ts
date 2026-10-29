import { contactShadow, glossyEye, oval, smallLeaf, softMaterial } from './creatureArt';

export interface BuddyAppearance { rolling?:boolean; moving?:boolean; waiting?:boolean; lowMotion?:boolean; ball?:HTMLImageElement; happy?:boolean }
/** A small sculpted mushroom with Luvie's coral cap, ivory palette and warm light. */
export function drawMushroomBuddy(c:CanvasRenderingContext2D,x:number,y:number,size:number,time:number,look:BuddyAppearance={}) {
 const t=look.lowMotion?0:time,breath=Math.sin(t/780),walk=look.moving?Math.sin(t/110):0;
 c.save();c.translate(x,y);c.scale(size/48,size/48);contactShadow(c,1,1,20,5);
 if(look.rolling&&look.ball?.complete&&look.ball.naturalWidth){
  c.translate(0,-18);if(!look.lowMotion)c.rotate(t/220);
  c.drawImage(look.ball,-20,-22,40,40*look.ball.naturalHeight/look.ball.naturalWidth);c.restore();return;
 }
 c.translate(0,look.lowMotion?0:breath*.65-Math.abs(walk)*1.8);
 if(look.waiting){c.translate(0,3);c.scale(1.045,.92);}
 oval(c,-6,-1+walk,5,2.8,softMaterial(c,-7,-2,6,'#e3c3a1','#b89170','#85674f'));
 oval(c,6,-1-walk,5,2.8,softMaterial(c,5,-2,6,'#e3c3a1','#b89170','#85674f'));
 c.fillStyle=softMaterial(c,-1,-13,15,'#fff8e7','#efdfba','#bba383');
 c.beginPath();c.moveTo(-10,-23);c.bezierCurveTo(-10,-15,-15,-4,-7,-2);c.quadraticCurveTo(0,1,8,-2);c.bezierCurveTo(14,-5,10,-17,10,-23);c.closePath();c.fill();
 for(let i=0;i<18;i++){const px=Math.sin(i*7.3)*8,py=-19+(i*7%16);oval(c,px,py,.35,.6,i%2?'#fff9e847':'#bca58432');}
 oval(c,0,-23,15.5,4.6,softMaterial(c,-3,-24,19,'#f1c5a2','#d49b78','#975e49'));
 c.save();c.beginPath();c.ellipse(0,-23,15.5,4.6,0,0,Math.PI*2);c.clip();
 c.strokeStyle='#a56d594c';c.lineWidth=.55;for(let i=-13;i<=13;i+=3){c.beginPath();c.moveTo(i*.35,-21);c.lineTo(i,-27);c.stroke();}c.restore();
 c.fillStyle=softMaterial(c,-5,-37,26,'#f59b73','#d85b44','#8f352d');
 c.beginPath();c.moveTo(-20,-25);c.bezierCurveTo(-20,-36,-10,-48,0,-47);c.bezierCurveTo(12,-47,24,-34,21,-25);c.bezierCurveTo(13,-18,-13,-18,-20,-25);c.fill();
 c.save();c.beginPath();c.moveTo(-20,-25);c.bezierCurveTo(-20,-36,-10,-48,0,-47);c.bezierCurveTo(12,-47,24,-34,21,-25);c.bezierCurveTo(13,-18,-13,-18,-20,-25);c.clip();
 if(look.ball?.complete&&look.ball.naturalWidth){
  // Reuse the supplied shaded mushroom surface, keeping standing and rolling in one style.
  c.drawImage(look.ball,-22,-48,44,44*look.ball.naturalHeight/look.ball.naturalWidth);
 }else for(const [px,py,rx,ry,a] of [[-6,-39,5.7,3.9,-.35],[12,-30,4.2,3.1,.45],[-15,-28,3,2.5,-.6],[6,-46,3.8,2.4,.2]]){
  oval(c,px+.3,py+.7,rx+.4,ry+.4,'#9e493b42',a);oval(c,px,py,rx,ry,softMaterial(c,px-1,py-1,rx*1.3,'#fff9e6','#f2dfbd','#d2b995'),a);
 }
 const sheen=c.createRadialGradient(-9,-39,0,-9,-39,20);sheen.addColorStop(0,'#fff0d62b');sheen.addColorStop(1,'#fff0d600');c.fillStyle=sheen;c.fillRect(-22,-49,46,32);
 for(let i=0;i<36;i++){const a=i*2.399,rr=3+Math.sqrt(i)*2.6;oval(c,Math.cos(a)*rr,-35+Math.sin(a)*rr*.58,.3,.45,i%3?'#ffdcba24':'#74352821');}
 c.restore();
 c.strokeStyle='#efb18c8c';c.lineWidth=1.1;c.beginPath();c.moveTo(-18,-25);c.quadraticCurveTo(0,-19,19,-25);c.stroke();
 const blink=!look.lowMotion&&t%5200>5010;
 glossyEye(c,-4.5,-13,blink||look.happy);glossyEye(c,4.5,-13,blink||look.happy);
 oval(c,-7.5,-9.6,2.4,1.3,'#db9b805a');oval(c,7.5,-9.6,2.4,1.3,'#db9b805a');
 c.strokeStyle='#9c7155';c.lineWidth=.8;c.beginPath();c.arc(0,-10,1.8,.15,Math.PI-.15);c.stroke();
 smallLeaf(c,10,-4,.65,-.5);oval(c,5,-4,2.9,2,softMaterial(c,5,-5,4,'#fff5dc','#dfc89e','#b89b76'));
 if(look.waiting){smallLeaf(c,15,-12,.55,-.6);c.strokeStyle='#799061';c.lineWidth=.9;c.beginPath();c.moveTo(9,-4);c.lineTo(14,-11);c.stroke();}
 c.restore();
}
