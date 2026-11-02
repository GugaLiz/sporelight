import {oval,softMaterial,smallLeaf} from '../game/creatureArt';

export function drawBell(c:CanvasRenderingContext2D,x:number,y:number,scale:number){
 c.save();c.translate(x,y);c.scale(scale,scale);
 const gold=c.createLinearGradient(-12,-35,14,0);gold.addColorStop(0,'#fff0b0');gold.addColorStop(.5,'#deb56a');gold.addColorStop(1,'#a87b41');
 c.strokeStyle='#ab8751';c.lineWidth=3;c.beginPath();c.arc(0,-35,5,Math.PI,0);c.stroke();c.fillStyle=gold;
 c.beginPath();c.moveTo(-14,-7);c.quadraticCurveTo(-8,-14,-9,-25);c.quadraticCurveTo(0,-39,9,-25);c.quadraticCurveTo(8,-14,14,-7);c.closePath();c.fill();c.stroke();
 oval(c,0,-7,14,4,'#9b743e');oval(c,0,-5,4,4,'#efd49b');c.restore();
}

/** Draw in the character's local body transform, so nothing orbits the character. */
export function drawCarryBag(c:CanvasRenderingContext2D,item:string,scale:number,images:Map<string,HTMLImageElement>,buddy=false,rolling=false,pose='idle-front'){
 c.save();c.scale(scale,scale);if(rolling)c.translate(0,31);if(buddy)c.scale(.66,.66);
 // Crouching artwork moves the waist forward and down relative to the feet.
 if(!buddy&&!rolling){if(pose==='interact'||pose.startsWith('sow-'))c.translate(8,7);else if(['lean','salute','symbiosis'].includes(pose))c.translate(3,4);}
 // Only a front-facing torso exposes the cord. Side poses hide it behind the arm.
 const showCord=buddy||!rolling&&(pose==='idle-front'||/^walk-(1|2|7|8|9|10|11|12)$/.test(pose));
 if(showCord){
  c.lineCap='round';c.strokeStyle='#7c8862';c.lineWidth=1.6;c.beginPath();c.moveTo(0,-31);c.bezierCurveTo(1,-28,4,-26,7,-23);c.stroke();
  c.strokeStyle='#bdc69a';c.lineWidth=.5;c.beginPath();c.moveTo(-.3,-31);c.bezierCurveTo(.7,-28,3.7,-26,6.7,-23);c.stroke();
 }
 // Reduce the pouch itself and draw it against the dress, above the hem.
 c.save();c.translate(7,-18);c.scale(.65,.65);c.translate(-12,20);
 const image=(key:string,x:number,y:number,width:number,anchor=1)=>{const im=images.get(key);if(im?.complete&&im.naturalWidth)c.drawImage(im,x-width/2,y-width*im.naturalHeight/im.naturalWidth*anchor,width,width*im.naturalHeight/im.naturalWidth);};
 if(item==='dew')image('dew-parcel',12,-8,25);
 else{
  oval(c,12,-18,12,10,softMaterial(c,8,-22,16,'#d0d598','#91a364','#596d48'));
  oval(c,12,-26,10,3.7,'#576746');
  if(item==='bell')drawBell(c,12,-17,.45);
  else image(item==='lamp'?'light':item.startsWith('mirror')?'lilypad':'crystal',12,-20,18,.72);
  smallLeaf(c,5,-12,.8,-1.1);smallLeaf(c,17,-11,.85,-.3);
  c.strokeStyle='#d3d5a17c';c.lineWidth=.7;c.beginPath();c.moveTo(5,-10);c.quadraticCurveTo(12,-6,20,-14);c.stroke();
 }
 // A little leaf clasp makes the connection to the strap visible.
 c.restore();if(showCord)oval(c,6,-23,1.1,.8,'#b8bd87',-.6);c.restore();
}
