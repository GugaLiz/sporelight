/** Warm light from the upper left, shared by the two little forest creatures. */
export function oval(c:CanvasRenderingContext2D,x:number,y:number,rx:number,ry:number,fill:string|CanvasGradient,rotation=0) {
 c.fillStyle=fill;c.beginPath();c.ellipse(x,y,rx,ry,rotation,0,Math.PI*2);c.fill();
}
export function softMaterial(c:CanvasRenderingContext2D,x:number,y:number,r:number,light:string,base:string,shade:string) {
 const g=c.createRadialGradient(x-r*.32,y-r*.4,r*.04,x+r*.18,y+r*.3,r*1.2);
 g.addColorStop(0,light);g.addColorStop(.48,base);g.addColorStop(1,shade);return g;
}
export function contactShadow(c:CanvasRenderingContext2D,x:number,y:number,rx:number,ry:number) {
 c.save();c.translate(x,y);c.scale(1,ry/rx);
 const g=c.createRadialGradient(0,0,0,0,0,rx);g.addColorStop(0,'#38473759');g.addColorStop(.55,'#38473724');g.addColorStop(1,'#38473700');
 oval(c,0,0,rx,rx,g);c.restore();
}
export function glossyEye(c:CanvasRenderingContext2D,x:number,y:number,closed=false,size=1) {
 if(closed){c.strokeStyle='#584437';c.lineWidth=1.1;c.lineCap='round';c.beginPath();c.arc(x,y-1,2*size,.15,Math.PI-.15);c.stroke();return;}
 oval(c,x,y,2.1*size,2.8*size,'#ddbea0');
 oval(c,x,y-.25,1.65*size,2.2*size,softMaterial(c,x,y,3*size,'#715744','#392e29','#211f20'));
 oval(c,x-.55*size,y-1.1*size,.6*size,.8*size,'#fff6e8');
 oval(c,x+.5*size,y+.65*size,.25*size,.3*size,'#d7bfa0');
}
export function smallLeaf(c:CanvasRenderingContext2D,x:number,y:number,size:number,angle=0) {
 c.save();c.translate(x,y);c.rotate(angle);c.scale(size,size);
 c.fillStyle=softMaterial(c,0,-2,10,'#c5d29b','#8caa72','#516d50');
 c.beginPath();c.moveTo(-8,3);c.quadraticCurveTo(-10,-6,7,-8);c.quadraticCurveTo(11,1,-8,3);c.fill();
 c.strokeStyle='#d7ddb280';c.lineWidth=.65;c.beginPath();c.moveTo(-7,2);c.lineTo(5,-6);c.stroke();c.restore();
}
