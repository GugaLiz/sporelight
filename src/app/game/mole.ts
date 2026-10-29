import { contactShadow, glossyEye, oval, smallLeaf, softMaterial } from './creatureArt';

/** A velvet woodland neighbour with clay-like volume, small paws and a leaf collar. */
export function drawMole(c:CanvasRenderingContext2D,x:number,y:number,size:number,time:number,look:{greet?:boolean;lowMotion?:boolean}={}) {
 const t=look.lowMotion?0:time,bob=Math.sin(t/950)*.65;
 c.save();c.translate(x,y);c.scale(size/62,size/62);contactShadow(c,0,1,30,9);
 oval(c,0,1,29,10,softMaterial(c,-4,-2,32,'#b1a17a','#877557','#594e3e'));
 oval(c,0,-1,23,6,'#514638');
 for(let i=0;i<9;i++){const a=i*.65;oval(c,Math.cos(a)*26,Math.sin(a)*6,4+(i%3),2.5,softMaterial(c,0,-5,35,'#b7c18e','#8b9d68','#5b714e'),a*.3);}
 c.translate(0,bob);
 oval(c,-16,-22,3.4,4,softMaterial(c,-15,-25,6,'#d5baa0','#a98c72','#785f50'));
 oval(c,16,-22,3.4,4,softMaterial(c,15,-25,6,'#d5baa0','#a98c72','#785f50'));
 oval(c,0,-15,20,22,softMaterial(c,-6,-24,26,'#dfccb0','#aa9278','#574d43'));
 c.save();c.beginPath();c.ellipse(0,-15,20,22,0,0,Math.PI*2);c.clip();
 for(let i=0;i<280;i++){const a=i*2.399,r=Math.sqrt(i)*1.4,px=Math.cos(a)*r,py=-16+Math.sin(a)*r;c.strokeStyle=i%3?'#f4dec119':'#5b49351c';c.lineWidth=.35;c.beginPath();c.moveTo(px,py);c.lineTo(px+.3,py+.85);c.stroke();}c.restore();
 oval(c,-1,-8,12,9,softMaterial(c,-4,-13,17,'#efddbd','#cdb594','#99816a'));
 const blink=!look.lowMotion&&t%6100>5920;
 glossyEye(c,-8,-19,blink,.95);glossyEye(c,8,-19,blink,.95);
 oval(c,0,-11,5.2,3.7,softMaterial(c,-2,-13,7,'#eac0aa','#bc8975','#825c50'));
 oval(c,-1.6,-12.3,1.4,.65,'#f5ddc6a6');
 c.strokeStyle='#78604b';c.lineWidth=.8;c.beginPath();c.moveTo(0,-7);c.lineTo(0,-5);c.quadraticCurveTo(3,-3,5,-5);c.stroke();
 for(const side of [-1,1])for(let i=0;i<2;i++){c.strokeStyle='#dbccb099';c.lineWidth=.55;c.beginPath();c.moveTo(side*9,-9+i*3);c.lineTo(side*(19+i*2),-11+i*6);c.stroke();}
 smallLeaf(c,-6,-1,.85,.4);smallLeaf(c,5,-1,.8,1.1);
 for(const side of [-1,1]){c.save();c.translate(side*18,look.greet&&side===1?-9+Math.sin(t/250)*2:0);c.rotate(side*.2);
  oval(c,0,0,6.7,4.6,softMaterial(c,-2,-2,9,'#ebd2b6','#c2a284','#8a6e58'));
  for(let i=0;i<3;i++)oval(c,-3+i*2.5,2.5,.85,1.7,'#ecddc1');c.restore();}
 c.restore();
}
