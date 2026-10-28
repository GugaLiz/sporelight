export interface BuddyAppearance { rolling?:boolean; waiting?:boolean; lowMotion?:boolean; ball?:HTMLImageElement; happy?:boolean }
/** Red cap and cream stem from reference 3; supplied mushroom-ball art from reference 2. */
export function drawMushroomBuddy(c:CanvasRenderingContext2D,x:number,y:number,size:number,time:number,look:BuddyAppearance={}) {
  c.save();c.translate(x,y);c.scale(size/42,size/42);
  c.fillStyle='#3e4e422a';c.beginPath();c.ellipse(0,1,15,4.5,0,0,Math.PI*2);c.fill();
  if(look.rolling&&look.ball?.complete&&look.ball.naturalWidth){
    c.translate(0,-16);if(!look.lowMotion)c.rotate(Math.sin(time*.006)*.28);
    c.drawImage(look.ball,-20,-20,40,40*look.ball.naturalHeight/look.ball.naturalWidth);c.restore();return;
  }
  if(!look.lowMotion)c.translate(0,Math.sin(time*.003)*1.1);
  const ellipse=(a:number,b:number,w:number,h:number,color:string)=>{c.fillStyle=color;c.beginPath();c.ellipse(a,b,w,h,0,0,Math.PI*2);c.fill();};
  ellipse(-5,-1,4,2.8,'#9e7961');ellipse(5,-1,4,2.8,'#9e7961');
  ellipse(0,look.waiting?-9:-11,10,look.waiting?9:11,'#f7e8c6');
  c.fillStyle='#c85740';c.beginPath();c.moveTo(-17,-20);c.bezierCurveTo(-20,-29,-8,-41,0,-39);c.bezierCurveTo(9,-39,22,-27,17,-20);c.quadraticCurveTo(0,-15,-17,-20);c.fill();
  ellipse(-5,-31,5.4,3.7,'#fff1da');ellipse(9,-25,3.4,3,'#ffebd3');ellipse(-13,-23,2.4,2,'#f8e7d2');
  ellipse(0,-19,14.5,3,'#df9e75');ellipse(-4,-12,1.6,2.2,'#5f5145');ellipse(4,-12,1.6,2.2,'#5f5145');
  ellipse(-7,-8,2.5,1.4,'#e7b59a');ellipse(7,-8,2.5,1.4,'#e7b59a');
  c.strokeStyle='#9e7456';c.lineWidth=1;c.beginPath();c.arc(0,-9,2,0,Math.PI);c.stroke();
  if(look.waiting){c.strokeStyle='#819464';c.lineWidth=2;c.beginPath();c.moveTo(10,-3);c.lineTo(16,-9);c.stroke();ellipse(17,-11,5,2.5,'#9cae7e');}
  if(look.happy){c.fillStyle='#dfad7d';c.font='13px serif';c.fillText('♡',15,-33);}
  c.restore();
}
