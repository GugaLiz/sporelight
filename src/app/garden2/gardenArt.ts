import {oval,softMaterial,contactShadow,smallLeaf} from '../game/creatureArt';

function texturedOval(c:CanvasRenderingContext2D,x:number,y:number,rx:number,ry:number,image?:HTMLImageElement,alpha=.32){
 if(!image?.complete||!image.naturalWidth)return;
 c.save();c.beginPath();c.ellipse(x,y,rx,ry,0,0,Math.PI*2);c.clip();c.globalAlpha=alpha;c.drawImage(image,x-rx,y-ry,rx*2,ry*2);c.restore();
}

/** Weathered sandstone and moss borrow actual terrain grain; the water stays translucent. */
export function drawFountain(c:CanvasRenderingContext2D,x:number,y:number,size:number,time:number,particles:boolean,stone?:HTMLImageElement){
 c.save();c.translate(x,y);c.scale(size/90,size/90);contactShadow(c,0,8,48,17);

 oval(c,0,2,43,20,softMaterial(c,-8,-8,51,'#fff4dc','#e6d0a9','#b7a180'));
 texturedOval(c,0,2,43,20,stone,.08);
 c.strokeStyle='#c4b28d';c.lineWidth=1.1;c.beginPath();c.ellipse(0,4,41,17,0,0,Math.PI);c.stroke();
 for(let i=0;i<9;i++){const a=i/9*Math.PI*2,px=Math.cos(a)*39,py=Math.sin(a)*17;c.strokeStyle='#baaa8550';c.lineWidth=.8;c.beginPath();c.moveTo(px*.86,py*.8-4);c.lineTo(px,py);c.lineTo(px,py+4);c.stroke();}
 oval(c,0,-4,39,18,softMaterial(c,-9,-8,46,'#fff9e8','#ecdabb','#c8b18c'));
 texturedOval(c,0,-4,39,18,stone,.06);
 oval(c,0,-5,31,13,softMaterial(c,-8,-9,36,'#ecfbef','#a6dce0','#74b7c4'));
 const glint=c.createLinearGradient(-25,-10,22,2);glint.addColorStop(0,'#ffffff8c');glint.addColorStop(1,'#c5eeee29');oval(c,0,-5,29,11,glint);
 for(let i=0;i<3;i++){c.strokeStyle=i%2?'#dce6c464':'#eff3db71';c.lineWidth=.65;c.beginPath();c.ellipse(-2,-5,9+i*7+Math.sin(time*.002+i),3+i*2.5,-.06,0,Math.PI*1.7);c.stroke();}
 // Carved pedestal, lobed upper basin, and a small leaf nozzle.
 oval(c,0,-12,12,6,softMaterial(c,-4,-16,17,'#fff5dc','#e1cfaa','#bba681'));
 c.fillStyle=softMaterial(c,-3,-27,23,'#fff9e7','#e8d7b6','#c2ae8a');c.beginPath();c.moveTo(-9,-14);c.quadraticCurveTo(-3,-25,-7,-35);c.lineTo(7,-35);c.quadraticCurveTo(3,-25,9,-14);c.closePath();c.fill();
 c.strokeStyle='#eee5c17c';c.lineWidth=1.3;c.beginPath();c.moveTo(-4,-17);c.quadraticCurveTo(-1,-26,-3,-33);c.stroke();
 oval(c,0,-35,19,8,softMaterial(c,-6,-39,24,'#fff8e3','#e5d1aa','#bca680'));texturedOval(c,0,-35,19,8,stone,.08);oval(c,0,-37,13,4.8,'#bce6e2');
 smallLeaf(c,0,-44,.55,-.3);smallLeaf(c,3,-41,.45,1.6);
 c.save();c.lineCap='round';
 for(const side of [-1,1]){c.strokeStyle='#a6d7d57d';c.lineWidth=3;c.beginPath();c.moveTo(side*2,-42);c.quadraticCurveTo(side*12,-65,side*23,-10);c.stroke();c.strokeStyle='#effff2df';c.lineWidth=1.1;c.beginPath();c.moveTo(side*2-1,-43);c.quadraticCurveTo(side*11,-65,side*22,-11);c.stroke();}c.restore();
 if(particles)for(let i=0;i<7;i++){const t=(time*.00055+i/7)%1,side=i%2?1:-1;oval(c,side*(8+t*16),-50+t*38,1,1.6,'#dcebd5b5');}
 // Moss and tiny flowers soften the rim without hiding the basin.
 for(const [px,py,a]of [[-32,5,-.4],[28,9,.6],[-21,15,1.2]]){smallLeaf(c,px,py,.42,a);oval(c,px+4,py-1,1.7,1.3,'#f1d9ac');}
 c.restore();
}

export interface ButterflyAnchor{x:number;y:number}
const restingSpots:ButterflyAnchor[]=[{x:-95,y:-5},{x:-45,y:30},{x:55,y:12},{x:75,y:-45},{x:-25,y:-62}];
export function butterflyPose(index:number,time:number,anchors:ButterflyAnchor[]=restingSpots){
 const spots=anchors.length>=2?anchors:restingSpots,group=index<2?index:2,duration=[34000,41000,46000][group],offset=[0,19000,14000][group];
 const elapsed=time+offset,cycle=Math.floor(elapsed/duration),phase=elapsed%duration/duration;
 const a=spots[(cycle+group*2)%spots.length],b=spots[(cycle+group*2+1)%spots.length],perched=phase<.38,u=perched?0:(phase-.38)/.62;
 const position=(p:number)=>{const ease=p*p*(3-2*p),arc=Math.sin(p*Math.PI);let x=a.x+(b.x-a.x)*ease,y=a.y+(b.y-a.y)*ease-arc*22;
  if(index>=2){const sign=index===2?-1:1;x+=sign*(Math.cos(p*Math.PI*3)*15*arc+5);y+=sign*Math.sin(p*Math.PI*3)*10*arc;}
  else{x+=Math.sin(p*Math.PI*2+index)*10*arc;y+=Math.sin(p*Math.PI*2)*4*arc;}
  return{x,y};};
 const point=position(u),next=position(Math.min(1,u+.004));
 return {...point,perched,size:[.64,.84,1.05,.73][index],heading:perched?-.5+index*.45:Math.atan2(next.y-point.y,next.x-point.x)+Math.PI/2,wingAngle:perched?1.05+Math.sin(time*.002+index)*.12:Math.sin(time*Math.PI*2/[1000,1180,1100,1280][index]+index*1.7)*1.35};
}

export function drawButterflies(c:CanvasRenderingContext2D,x:number,y:number,scale:number,time:number,anchors?:ButterflyAnchor[]){
 c.save();c.translate(x,y);c.scale(scale,scale);
 for(let i=0;i<4;i++){
  const pose=butterflyPose(i,time,anchors),flap=Math.cos(pose.wingAngle),lift=-Math.sin(pose.wingAngle)*.6;
  c.save();c.translate(pose.x,pose.y);c.rotate(pose.heading);c.scale(pose.size,pose.size);
  for(const side of [-1,1]){
   c.save();c.transform(side*flap,lift,0,1,0,0);
   const wing=softMaterial(c,4,-5,14,i%2?'#fff3cb':'#f9dfce',i%2?'#dcb574':'#d1a4a1',i%2?'#a58961':'#9b8284');
   c.fillStyle=wing;c.strokeStyle='#a48b6b';c.lineWidth=.55;c.beginPath();c.moveTo(0,0);c.bezierCurveTo(1,-8,9,-15,12,-9);c.bezierCurveTo(16,-2,8,2,2,2);c.bezierCurveTo(10,0,12,9,6,8);c.quadraticCurveTo(1,8,0,0);c.fill();c.stroke();
   c.strokeStyle='#816f5b64';c.lineWidth=.45;for(const [wx,wy]of [[10,-9],[11,-4],[7,5]]){c.beginPath();c.moveTo(1,0);c.quadraticCurveTo(5,-1,wx,wy);c.stroke();}
   oval(c,9,-7,1.7,2.3,'#b48f6e73',-.3);oval(c,10,-7.5,.75,1.2,'#f7e3bd');oval(c,5,5,1,.8,'#f7e5cc');c.restore();
  }
  oval(c,0,-.5,1.25,4.2,softMaterial(c,-1,-2,5,'#d1b88c','#8c795a','#514f40'));oval(c,0,-4.4,1.7,1.5,'#8c8062');
  c.strokeStyle='#897a5d';c.lineWidth=.6;for(const side of [-1,1]){c.beginPath();c.moveTo(0,-4);c.quadraticCurveTo(side*1,-8,side*3,-8);c.stroke();}c.restore();
 }c.restore();
}

export function drawLever(c:CanvasRenderingContext2D,x:number,y:number,size:number,pull:number,stone?:HTMLImageElement){
 c.save();c.translate(x,y);c.scale(size/70,size/70);contactShadow(c,0,4,28,10);
 const poly=(points:number[][],fill:string|CanvasGradient)=>{c.fillStyle=fill;c.beginPath();points.forEach(([px,py],i)=>i?c.lineTo(px,py):c.moveTo(px,py));c.closePath();c.fill();};
 poly([[-24,0],[0,12],[24,0],[0,-12]],'#dccbaa');poly([[-24,0],[0,12],[0,19],[-24,7]],'#ad9d7d');poly([[0,12],[24,0],[24,7],[0,19]],'#8c8e70');
 c.save();c.beginPath();c.moveTo(-24,0);c.lineTo(0,-12);c.lineTo(24,0);c.lineTo(0,12);c.closePath();c.clip();if(stone?.complete&&stone.naturalWidth){c.globalAlpha=.35;c.drawImage(stone,-28,-13,56,30);}c.restore();
 for(const side of [-1,1]){c.strokeStyle='#796747';c.lineWidth=7;c.lineCap='round';c.beginPath();c.moveTo(side*9,-2);c.lineTo(side*9,-19);c.stroke();c.strokeStyle='#c3ad75';c.lineWidth=2;c.beginPath();c.moveTo(side*9-1,-3);c.lineTo(side*9-1,-20);c.stroke();}
 const tx=-10+pull*31,ty=-61+pull*18;
 c.strokeStyle='#766345';c.lineWidth=7;c.lineCap='round';c.beginPath();c.moveTo(0,-15);c.lineTo(tx,ty);c.stroke();c.strokeStyle='#e1c488';c.lineWidth=2;c.beginPath();c.moveTo(-1,-17);c.lineTo(tx-1,ty+2);c.stroke();
 oval(c,0,-15,8,5,softMaterial(c,-2,-17,10,'#f1d799','#bea16a','#826e46'));oval(c,-1,-16,2.5,2,'#eed9a9');
 oval(c,tx,ty,9,6,softMaterial(c,tx-3,ty-3,12,'#f1b18b','#ce795b','#8f5140'));oval(c,tx-3,ty-2,3,1.8,'#f9d5ac');
 smallLeaf(c,-20,7,.36,-.5);if(pull)oval(c,19,-1,2.2,1.4,'#efda9f');c.restore();
}

export function drawLeafPlate(c:CanvasRenderingContext2D,x:number,y:number,size:number,pressed:boolean,time:number,stone?:HTMLImageElement,leaf?:HTMLImageElement){
 c.save();c.translate(x,y);c.scale(size/70,size/70);contactShadow(c,0,5,34,12);
 const drop=pressed?2:0;const poly=(points:number[][],fill:string|CanvasGradient)=>{c.fillStyle=fill;c.beginPath();points.forEach(([px,py],i)=>i?c.lineTo(px,py):c.moveTo(px,py));c.closePath();c.fill();};
 poly([[-31,0],[0,15],[31,0],[0,-15]],'#aaa88a');poly([[-31,0],[0,15],[0,20],[-31,5]],'#8d9276');poly([[0,15],[31,0],[31,5],[0,20]],'#6b7c65');
 c.save();c.beginPath();c.moveTo(-29,0);c.lineTo(0,-14);c.lineTo(29,0);c.lineTo(0,14);c.closePath();c.clip();if(stone?.complete&&stone.naturalWidth)c.drawImage(stone,-35,-17,70,35);c.restore();
 c.translate(0,drop);oval(c,0,-1,23,10,softMaterial(c,-7,-6,28,'#dce2b5','#a5b485','#708464'));
 if(leaf?.complete&&leaf.naturalWidth){c.save();c.globalAlpha=.92;c.drawImage(leaf,-24,-13,48,48*leaf.naturalHeight/leaf.naturalWidth);c.restore();}
 c.strokeStyle=pressed?'#f4df9c':'#d5dfae';c.lineWidth=1.3;c.beginPath();c.moveTo(-17,4);c.quadraticCurveTo(0,-1,18,-6);c.stroke();
 for(let i=-1;i<=1;i++){c.strokeStyle='#dce5b76b';c.lineWidth=.65;c.beginPath();c.moveTo(i*8,i*-2);c.lineTo(i*8-5,-7+i*-2);c.moveTo(i*8,i*-2);c.lineTo(i*8+5,6+i*-2);c.stroke();}
 if(pressed){c.strokeStyle='#efda9d';c.lineWidth=1.2;c.beginPath();c.ellipse(0,0,28,13,0,0,Math.PI*2);c.stroke();for(const px of [-26,25])oval(c,px,-2,1.8,1.3,'#ffe7ac');}
 smallLeaf(c,-26,4,.3,-.7);c.restore();
}
