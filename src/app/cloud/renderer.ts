import { cloudTiles, type CloudTile, type Point } from './data';
import { CloudModel, type CloudState } from './model';
import type { SaveData } from '../types';
export interface CloudAnimation { from:CloudState; to:CloudState; progress:number; kind:string }
type ScreenPoint={x:number;y:number};
const mix=(a:number,b:number,t:number)=>a+(b-a)*t;
const smooth=(t:number)=>t*t*(3-2*t);

/** Original vector architecture and characters, with no image/texture dependencies. */
export class CloudRenderer {
  private c:CanvasRenderingContext2D;
  width=1280;height=720;scale=1;ox=0;oy=0;
  private clock=0;
  constructor(readonly canvas:HTMLCanvasElement,readonly model:CloudModel,private settings:SaveData['settings']){this.c=canvas.getContext('2d')!;this.resize();}
  configure(s:SaveData['settings']){this.settings=s;this.resize();}
  resize(){
    this.width=this.canvas.clientWidth||1280;this.height=this.canvas.clientHeight||720;
    const ratio=this.settings.quality==='soft'?1:Math.min(window.devicePixelRatio||1,2);
    this.canvas.width=this.width*ratio;this.canvas.height=this.height*ratio;this.c.setTransform(ratio,0,0,ratio,0,0);
    const all=[...cloudTiles(this.model.id,'north','low',true),...cloudTiles(this.model.id,'east','high',true)];
    const points=all.map(p=>this.raw(p));const minX=Math.min(...points.map(p=>p.x))-70,maxX=Math.max(...points.map(p=>p.x))+70;
    const minY=Math.min(...points.map(p=>p.y))-165,maxY=Math.max(...points.map(p=>p.y))+135;
    const preview=!!this.canvas.dataset.cloudPreview,portrait=this.width<650,usableW=this.width-(preview?30:portrait?28:280),usableH=this.height-(preview?45:portrait?320:185);
    this.scale=Math.min(preview?.8:portrait?1.05:1.4,usableW/(maxX-minX),usableH/(maxY-minY));
    this.ox=(preview||portrait?this.width*.5:this.width*.58)-(minX+maxX)*this.scale/2;
    this.oy=(preview?this.height*.56:portrait?this.height*.46:this.height*.48)-(minY+maxY)*this.scale/2;
  }
  private raw(p:Point){return {x:(p.x-p.z)*29,y:(p.x+p.z)*14.5-p.h*28};}
  project(p:Point):ScreenPoint{const q=this.raw(p);return {x:this.ox+q.x*this.scale,y:this.oy+q.y*this.scale};}
  landmarkAnchor(l:ReturnType<CloudModel['landmarkPoint']>):ScreenPoint {
    const placed:ScreenPoint[]=[];
    for(const landmark of this.model.level.landmarks){
      const p=this.project(this.model.landmarkPoint(landmark)),base={x:p.x,y:p.y-31*this.scale};let anchor=base;
      // Layout native-size touch targets, rather than scaling their hit areas with the world.
      if(this.width<900){
        const offsets=[[0,0],[-48,0],[48,0],[0,-48],[0,48],[-48,-48],[48,-48],[-48,48],[48,48],[-96,0],[96,0]];
        const offset=offsets.find(([dx,dy])=>base.x+dx>=24&&base.x+dx<=this.width-24&&base.y+dy>=190&&base.y+dy<this.height-155&&!placed.some(a=>Math.abs(a.x-base.x-dx)<46&&Math.abs(a.y-base.y-dy)<46));
        if(offset)anchor={x:base.x+offset[0],y:base.y+offset[1]};
      }
      if(landmark.id===l.id)return anchor;placed.push(anchor);
    }
    const p=this.project(l);return {x:p.x,y:p.y-31*this.scale};
  }
  private poly(points:number[][],fill:string,stroke?:string){const c=this.c;c.beginPath();points.forEach(([x,y],i)=>i?c.lineTo(x,y):c.moveTo(x,y));c.closePath();c.fillStyle=fill;c.fill();if(stroke){c.strokeStyle=stroke;c.lineWidth=.65;c.stroke();}}
  private ellipse(x:number,y:number,rx:number,ry:number,fill:string){const c=this.c;c.beginPath();c.ellipse(x,y,rx,ry,0,0,Math.PI*2);c.fillStyle=fill;c.fill();}
  private line(points:number[][],color:string,width=2){const c=this.c;c.beginPath();points.forEach(([x,y],i)=>i?c.lineTo(x,y):c.moveTo(x,y));c.strokeStyle=color;c.lineWidth=width;c.lineCap='round';c.lineJoin='round';c.stroke();}
  private box(x:number,y:number,w:number,d:number,h:number,top='#faf5e8',left='#e1d6c4',right='#c7c6b6'){
    this.poly([[x-w,y],[x,y+d],[x,y+d+h],[x-w,y+h]],left);
    this.poly([[x,y+d],[x+w,y],[x+w,y+h],[x,y+d+h]],right);
    this.poly([[x,y-d],[x+w,y],[x,y+d],[x-w,y]],top);
  }
  private flowers(x:number,y:number,count=5){
    for(let i=0;i<count;i++){const xx=x+Math.sin(i*8)*13,yy=y+Math.cos(i*3)*5;this.line([[xx,yy],[xx-2,yy-8]],'#8da88a',1.5);this.ellipse(xx-2,yy-9,3,2.5,i%2?'#f1beac':'#f6dda5');this.ellipse(xx-2,yy-9,1,1,'#fff8dc');}
  }
  private cloud(x:number,y:number,w:number,alpha=.35){const c=this.c;c.save();c.globalAlpha=alpha;this.ellipse(x,y,w,w*.12,'#fffdf5');this.ellipse(x-w*.35,y-4,w*.45,w*.14,'#fffdf5');this.ellipse(x+w*.2,y-5,w*.5,w*.17,'#fffdf5');c.restore();}
  private background(){
    const c=this.c,w=this.width,h=this.height,colors=this.model.level.sky;
    const gradient=c.createLinearGradient(0,0,w*.5,h);gradient.addColorStop(0,colors[0]);gradient.addColorStop(1,colors[1]);c.fillStyle=gradient;c.fillRect(0,0,w,h);
    const glow=c.createRadialGradient(w*.65,h*.28,10,w*.65,h*.28,w*.65);glow.addColorStop(0,'#fffdf29c');glow.addColorStop(1,'#fffdf200');c.fillStyle=glow;c.fillRect(0,0,w,h);
    // Quiet, distant gardens establish scale without looking like walkable foreground.
    c.save();c.globalAlpha=.12;
    for(const [x,y,s]of [[w*.11,h*.32,.55],[w*.88,h*.22,.7],[w*.83,h*.75,.4]]){c.save();c.translate(x,y);c.scale(s,s);this.box(0,0,63,31,70,'#ffffef','#aabdb1','#9fafa7');this.box(12,-33,16,8,39,'#fff9eb','#abbcb0','#9bafa5');this.ellipse(-20,-10,12,8,'#8fae9d');c.restore();}c.restore();
    this.cloud(w*.22+Math.sin(this.clock*.000025)*9,h*.76,w*.17,.22);this.cloud(w*.79,h*.46,w*.12,.18);this.cloud(w*.48,h*.9,w*.24,.35);
    if(this.model.id==='cloud-3')for(let i=0;i<18;i++)this.star((i*137.5)%w,60+(i*71)%Math.max(100,h-180),i%3===0?2:1,'#fff9e9');
  }
  private star(x:number,y:number,r:number,color:string){this.poly([[x,y-r*3],[x+r*.7,y-r*.7],[x+r*3,y],[x+r*.7,y+r*.7],[x,y+r*3],[x-r*.7,y+r*.7],[x-r*3,y],[x-r*.7,y-r*.7]],color);}
  private tile(t:CloudTile,all:CloudTile[]){
    const {x,y}=this.raw(t),w=29,d=14.5,depth=t.kind==='bridge'||t.kind==='gate'?11:74+t.h*18;
    const has=(dx:number,dz:number)=>all.some(b=>b.x===t.x+dx&&b.z===t.z+dz&&Math.abs(b.h-t.h)<.1);
    const top=t.kind==='bridge'?'#ebd6c2':t.kind==='lift'?'#cadcce':t.kind==='gate'?'#e5d8cb':'#faf5e9';
    if(!has(0,1))this.poly([[x-w,y],[x,y+d],[x,y+d+depth],[x-w,y+depth]],t.kind==='bridge'?'#c5aa96':'#e2d8c8');
    if(!has(1,0))this.poly([[x,y+d],[x+w,y],[x+w,y+depth],[x,y+d+depth]],t.kind==='bridge'?'#b59a8a':'#c6c7b6');
    this.poly([[x,y-d],[x+w,y],[x,y+d],[x-w,y]],top,'#eee6d733');
    if(t.kind==='stair')for(let i=-1;i<=1;i++)this.line([[x-w/2+i*7,y-d/2+i*3.5],[x+w/2+i*7,y+d/2+i*3.5]],'#cfc4b6',1);
    if(t.kind==='bridge')this.line([[x-w+3,y-1],[x,y-d+2],[x+w-3,y-1]],'#fff5e3',1.5);
    if(t.kind==='lift'){this.poly([[x-18,y],[x,y-9],[x+18,y],[x,y+9]],'#b2c9b5');this.ellipse(x,y,4,2,'#f8f2d3');}
    // A continuous coping along the exterior joins adjacent floor cells into a building.
    if(!has(0,-1))this.line([[x-w,y],[x,y-d]],'#fffdf6',2);
    if(!has(-1,0))this.line([[x,y-d],[x+w,y]],'#fffdf6',2);
  }
  private arch(x:number,y:number,scale=1,pink=false){
    const c=this.c;c.save();c.translate(x,y);c.scale(scale,scale);
    this.box(0,-54,34,14,55,pink?'#edcabc':'#f7eddb',pink?'#dcb7a6':'#e5d9c4','#bfc5b5');
    // Inset arch with a lit threshold. Decorative façade sits behind the path.
    c.fillStyle='#829e98';c.beginPath();c.moveTo(-13,0);c.lineTo(-13,-30);c.arc(0,-30,13,Math.PI,0);c.lineTo(13,0);c.closePath();c.fill();
    c.fillStyle='#b6c9ba';c.beginPath();c.moveTo(-8,0);c.lineTo(-8,-29);c.arc(2,-29,10,Math.PI,0);c.lineTo(12,0);c.closePath();c.fill();
    this.line([[-28,-54],[0,-68],[29,-54]],'#fff9ec',3);
    this.box(-24,-7,7,3.5,8,'#fff8e8','#e5d3bd','#c7bdab');this.box(24,-7,7,3.5,8,'#fff8e8','#e5d3bd','#c7bdab');
    c.restore();
  }
  private tower(p:Point,repaired:boolean){
    const {x,y}=this.raw(p),c=this.c;
    this.box(x,y-98,35,17.5,100,'#f5e8d6','#ecddcb','#d0c8b8');
    this.box(x,y-103,42,21,10,'#fff7e6','#e3c8b5','#c2bba8');
    this.box(x,y-145,26,13,42,'#f9efdd','#edcfb9','#c9bfae');
    this.poly([[x-32,y-145],[x,y-179],[x+32,y-145],[x,y-130]],'#c6a896');
    this.poly([[x,y-179],[x+32,y-145],[x,y-130]],'#b08d82');
    this.ellipse(x,y-122,7,9,'#83968b');this.ellipse(x,y-123,4,6,repaired?'#ffe4a4':'#c8c7af');
    this.arch(x,y+6,.78,true);
    if(repaired){
      this.line([[x-24,y+9],[x-30,y-40],[x-20,y-70],[x-25,y-110]],'#94aa82',4);
      for(let i=0;i<7;i++)this.flowers(x-24+Math.sin(i*2)*7,y-i*17,3);
      this.flowers(x+19,y-95,5);this.star(x,y-122,3,'#ffe6a2');
    }
    c.save();c.globalAlpha=.45;this.line([[x+15,y-73],[x+15,y-92]],'#fff9e9',5);c.restore();
  }
  private pool(p:Point,filled:boolean){
    const {x,y}=this.raw(p);this.box(x,y-3,42,21,12,'#f6efdc','#d9d5c1','#aebeb0');
    this.poly([[x-31,y-3],[x,y-18],[x+31,y-3],[x,y+12]],filled?'#94c3c5':'#d6d7bf');
    if(filled){this.line([[x-18,y-1],[x,y+7],[x+22,y-4]],'#dfefdf',1.5);this.ellipse(x-10,y-5,6,3,'#a2bc90');this.flowers(x-9,y-6,2);}
  }
  private bench(p:Point){const q=this.raw(p);this.box(q.x,q.y-6,20,10,8,'#d2b79c','#bfaa92','#a99782');this.line([[q.x-17,q.y-10],[q.x-17,q.y-18],[q.x+2,q.y-9]],'#d6c1a5',3);}
  private plant(p:Point,large=false){const {x,y}=this.raw(p);this.box(x,y-3,large?16:9,large?8:4.5,large?12:8,'#e2bdaa','#d2ae9b','#b6a58f');for(let i=0;i<5;i++)this.ellipse(x+Math.sin(i*2.3)*(large?10:6),y-11-i*3,large?10:6,large?6:4,i%2?'#a9b89a':'#8fa88d');}
  private scenery(repaired:boolean){
    if(this.model.id==='cloud-1'){
      this.plant({x:0,z:6,h:0},true);this.bench({x:2,z:8,h:0});this.arch(this.raw({x:3,z:-4,h:1}).x,this.raw({x:3,z:-4,h:1}).y,.8);
      this.tower({x:10,z:2,h:1},repaired);this.plant({x:11,z:4,h:1});this.plant({x:5,z:2,h:1});
    }else if(this.model.id==='cloud-2'){
      this.arch(this.raw({x:3,z:3,h:0}).x,this.raw({x:3,z:3,h:0}).y,.9);
      this.pool({x:10,z:3,h:3},repaired);this.plant({x:8,z:3,h:3},true);this.bench({x:0,z:7,h:0});
      const c=this.c,q=this.raw({x:10,z:4,h:3});
      if(repaired){
        c.save();c.globalAlpha=.6;this.line([[q.x+38,q.y-5],[q.x+39,q.y+124]],'#badcda',12);this.line([[q.x+34,q.y-5],[q.x+35,q.y+123]],'#f0f4db',3);c.restore();
        for(let i=0;i<3;i++){const xx=q.x+35+i*5,yy=q.y+10+(this.clock*.035+i*38)%110;this.ellipse(xx,yy,1.8,4,'#edf7e7');}
        const b=this.raw({x:11,z:3,h:3});this.ellipse(b.x,b.y-9,7,5,'#eee6cb');this.ellipse(b.x+5,b.y-13,4,4,'#f8edce');this.poly([[b.x+8,b.y-14],[b.x+13,b.y-12],[b.x+8,b.y-10]],'#d9ad7f');this.ellipse(b.x+6,b.y-14,1,1,'#666c61');
      }
    }else{
      this.arch(this.raw({x:7,z:5,h:1}).x,this.raw({x:7,z:5,h:1}).y,.95,true);
      this.bench({x:8,z:-1,h:1});this.plant({x:9,z:7,h:1});this.plant({x:13,z:4,h:1});
      const q=this.raw({x:8,z:-1,h:1});this.line([[q.x-30,q.y-43],[q.x,q.y-33],[q.x+35,q.y-43]],'#a6a798',1);
      for(let i=0;i<5;i++){const x=q.x-28+i*15,y=q.y-40+Math.sin(i/4*Math.PI)*9;this.ellipse(x,y,3,5,repaired?'#ffe8ad':'#c4beb6');if(repaired)this.star(x,y,2,'#fff3c7');}
      if(repaired)for(let i=0;i<3;i++){const p=this.raw({x:8+i*.6,z:-1-i*.4,h:1});this.star(p.x,p.y-70-i*24,3,'#fff2c2');}
    }
    if(repaired)for(const t of this.model.tiles.filter(t=>t.kind==='floor'&&(t.x*7+t.z*13)%11===0))this.flowers(this.raw(t).x,this.raw(t).y,5);
  }
  private marker(l:ReturnType<CloudModel['landmarkPoint']>,active:boolean,found:boolean){
    const {x,y}=this.raw(l),c=this.c;c.save();
    if(l.id==='turn'){
      this.box(x,y-3,13,6.5,8,'#e6d6bd','#c5b59e','#b9b7a0');this.ellipse(x,y-4,8,4,'#c7b58e');this.line([[x-7,y-4],[x+7,y-4]],'#fff4d5',2);
    }else if(l.id==='pad'){
      this.poly([[x-18,y],[x-2,y-9],[x+18,y],[x+2,y+10]],'#a8bc98');this.line([[x-12,y],[x+12,y]],'#e1e6be',1);
    }else if(l.id==='valve'||l.id==='dock'){
      this.ellipse(x,y,9,5,'#b4c9b7');this.line([[x,y],[x,y-16]],'#8caa9c',3);this.ellipse(x,y-17,8,5,'#e4cc9f');
    }else if(l.id==='finish'){
      this.ellipse(x,y,16,8,'#d7d6b7');this.ellipse(x,y-3,11,6,this.model.state.repaired?'#a6bc94':'#bcbda3');
      this.star(x,y-17,4,this.model.state.repaired?'#fff0b5':'#ecdcaf');
    }else if(l.id==='seed'&&!this.model.state.seed){this.ellipse(x,y,9,5,'#c7d3b0');this.star(x,y-10,4,'#e4b692');}
    if(found){this.flowers(x,y,3);c.restore();return;}
    if(l.id==='seed'&&this.model.state.seed){c.restore();return;}
    if(l.id==='finish'&&this.model.state.repaired){c.restore();return;}
    const anchor=this.landmarkAnchor(l),base=this.project(l),offset=(anchor.x-base.x)/this.scale,offsetY=(anchor.y-(base.y-31*this.scale))/this.scale;
    const bounce=this.settings.lowMotion?0:Math.sin(this.clock*.0018+l.x)*2;
    if(active){this.ellipse(x,y,19,9,'#fff6d355');this.line([[x-19,y],[x,y+9],[x+19,y]],'#fff5ce',1.8);}
    if(offset||offsetY)this.line([[x,y-10],[x+offset,y-31+offsetY]],'#91a38c55',1);
    const radius=this.width<650?12/this.scale:l.story?9:11;
    this.ellipse(x+offset,y-31+offsetY+bounce,radius,radius,active?'#fff9e7':'#fff8e6dc');
    c.fillStyle=l.story?'#9ba68c':this.model.level.accent;c.font=`${(l.story?11:15)/Math.min(1,this.scale)}px Georgia,serif`;c.textAlign='center';c.textBaseline='middle';c.fillText(l.icon,x+offset,y-31+offsetY+bounce);
    c.restore();
  }
  private actor(p:Point,buddy:boolean,pose:string){
    const {x,y}=this.raw(p),c=this.c,walk=pose==='walk'?Math.sin(this.clock*.018):0;
    const bob=this.settings.lowMotion?0:pose==='happy'?Math.abs(Math.sin(this.clock*.007))*9:(buddy?Math.sin(this.clock*.003)*1.5:Math.abs(walk)*2);
    c.save();c.translate(x,y-bob);this.ellipse(0,1,buddy?10:12,buddy?4:4.5,'#6d817c24');
    if(buddy){
      this.ellipse(-5,0,4,2.5,'#849c79');this.ellipse(6,-walk,4,2.5,'#849c79');
      this.ellipse(0,-10,13,12,'#a9bd91');this.ellipse(-3,-11,11,10,'#c5d3ac');
      this.ellipse(-5,-12,1.4,1.8,pose==='sleep'?'#98a281':'#536758');this.ellipse(4,-12,1.4,1.8,pose==='sleep'?'#98a281':'#536758');
      this.ellipse(-7,-8,2.5,1.3,'#dbb2a1');this.ellipse(6,-8,2.5,1.3,'#dbb2a1');
      this.line([[0,-21],[0,-27]],'#8d9d6f',1.8);this.ellipse(5,-27,6,3,'#93ac81');this.ellipse(-3,-29,4,2,'#b5c39b');
    }else{
      this.ellipse(-5,pose==='sit'?3:walk*2-1,3.8,3,'#8f7c70');this.ellipse(5,pose==='sit'?3:-walk*2-1,3.8,3,'#8f7c70');
      this.poly([[-7,-25],[7,-25],[12,-6],[0,-3],[-12,-6]],'#9eafa0');this.poly([[0,-25],[7,-25],[12,-6],[0,-3]],'#879f94');
      this.ellipse(-10,-16+walk*2,3,4,'#f4e6cc');
      if(pose==='wave'||pose==='pet'||pose==='happy')this.line([[9,-18],[15,-25],[15,-31]],'#f6e8cd',5);else this.ellipse(10,-16-walk*2,3,4,'#f4e6cc');
      this.ellipse(0,-28,9,10,'#fff0d6');this.ellipse(-3,-27,1.2,1.7,'#655e56');this.ellipse(4,-27,1.2,1.7,'#655e56');this.ellipse(-5,-24,2.3,1.1,'#eab9a8');
      // Broad, asymmetrical mushroom cap is her original Sporelight silhouette.
      c.beginPath();c.moveTo(-17,-33);c.bezierCurveTo(-18,-53,6,-58,14,-38);c.quadraticCurveTo(22,-30,0,-30);c.quadraticCurveTo(-12,-29,-17,-33);c.fillStyle='#ce9d8c';c.fill();
      this.ellipse(-4,-44,5,3.2,'#f1d3ba');this.ellipse(8,-37,3.3,2.3,'#f2d5bd');this.line([[-14,-33],[0,-31],[15,-33]],'#ecc9ac',1.4);
      this.poly([[0,-21],[4,-19],[0,-16],[-4,-19]],'#e4c7a0');
    }
    if(pose==='pet'||pose==='wave'){this.star(17,-41,2,'#d29d91');this.star(-16,-30,1.4,'#dfba9b');}
    c.restore();
  }
  draw(time:number,animation?:CloudAnimation,pose='idle',hint?:string){
    this.clock=this.settings.lowMotion?0:time;this.background();
    const c=this.c,s=this.model.state,t=animation?smooth(animation.progress):0;
    let tiles=this.model.tiles;
    if(animation&&(animation.kind==='rotate'||animation.kind==='lift')){
      const dest=cloudTiles(this.model.id,animation.to.bridge,animation.to.lift,animation.to.latch||animation.to.buddy==='wait');
      tiles=tiles.map(tile=>{
        if(tile.kind==='lift')return {...tile,h:mix(tile.h,dest.find(d=>d.id===tile.id)!.h,t)};
        if(tile.kind==='bridge'&&animation.kind==='rotate'){
          const old=tiles.filter(a=>a.kind==='bridge').sort((a,b)=>a.x-b.x||a.z-b.z),next=dest.filter(a=>a.kind==='bridge').sort((a,b)=>a.x-b.x||a.z-b.z);
          const pivot=this.model.id==='cloud-1'?{x:4,z:3}:{x:8,z:5};
          const orderedOld=old.sort((a,b)=>Math.hypot(a.x-pivot.x,a.z-pivot.z)-Math.hypot(b.x-pivot.x,b.z-pivot.z));
          const orderedNext=next.sort((a,b)=>Math.hypot(a.x-pivot.x,a.z-pivot.z)-Math.hypot(b.x-pivot.x,b.z-pivot.z));
          const b=orderedNext[orderedOld.findIndex(a=>a.id===tile.id)],angle=animation.from.bridge==='north'?-Math.PI/2+t*Math.PI/2:-t*Math.PI/2;
          const radius=mix(Math.hypot(tile.x-pivot.x,tile.z-pivot.z),Math.hypot(b.x-pivot.x,b.z-pivot.z),t);
          return {...tile,x:pivot.x+Math.cos(angle)*radius,z:pivot.z+Math.sin(angle)*radius};
        }
        return tile;
      });
    }
    c.save();c.translate(this.ox,this.oy);c.scale(this.scale,this.scale);
    // Ground shadow and a few low clouds create a floating garden without a noisy texture.
    this.ellipse(0,260,270,42,'#657c7612');
    for(const tile of [...tiles].sort((a,b)=>(a.x+a.z)-(b.x+b.z)))this.tile(tile,tiles);
    this.scenery(s.repaired);
    const turn=this.model.level.landmarks.find(l=>l.id==='turn');
    if(turn&&this.model.near(turn)&&!animation&&!s.repaired){
      const preview=cloudTiles(this.model.id,s.bridge==='north'?'east':'north',s.lift,s.latch||s.buddy==='wait').filter(t=>t.kind==='bridge');
      c.save();c.globalAlpha=.42;c.setLineDash([3,4]);
      for(const tile of preview){const p=this.raw(tile);this.line([[p.x-25,p.y],[p.x,p.y-12],[p.x+25,p.y],[p.x,p.y+12],[p.x-25,p.y]],'#a88b71',1.5);}
      c.restore();
    }
    if(hint){const l=this.model.level.landmarks.find(l=>l.id===hint);if(l){const p=this.raw(this.model.landmarkPoint(l));this.ellipse(p.x,p.y,24,12,'#ffe8a655');this.line([[p.x-24,p.y],[p.x,p.y+12],[p.x+24,p.y]],'#e2bc77',2);}}
    for(const l of this.model.level.landmarks)this.marker(this.model.landmarkPoint(l),this.model.near(l),s.found.includes(l.id));
    let player:Point={...this.model.current};
    if(animation?.kind==='walk'){
      const a=tiles.find(a=>a.id===animation.from.tile)!,b=tiles.find(b=>b.id===animation.to.tile)!;
      player={x:mix(a.x,b.x,t),z:mix(a.z,b.z,t),h:mix(a.h,b.h,t)};
    }else if(animation?.kind==='lift'&&this.model.current.kind==='lift')player={...player,h:mix(animation.from.lift==='low'?0:3,animation.to.lift==='low'?0:3,t)};
    let buddy:Point={...player,x:player.x-.4,z:player.z+.42};
    if(s.buddy==='sleep')buddy={x:10.75,z:3,h:1};
    if(s.buddy==='wait')buddy={x:3,z:6,h:1};
    if(s.repaired){const finish=this.model.level.landmarks.find(l=>l.id==='finish')!;player={...finish,x:finish.x-.35};buddy={...finish,x:finish.x+.4,z:finish.z+.35};}
    this.actor(player,false,s.repaired?(pose==='happy'?'happy':'sit'):pose);
    this.actor(buddy,true,s.repaired?'sit':s.buddy==='sleep'?'sleep':pose==='pet'?'pet':s.buddy==='follow'?pose:'idle');
    if(s.repaired&&this.settings.particles)for(let i=0;i<16;i++){const p=this.raw(player);this.star(p.x+Math.sin(i*17)*130,p.y-30-(this.clock*.015+i*19)%180,i%3?1:2,'#fff0c0');}
    c.restore();
  }
  hit(x:number,y:number):CloudTile|undefined{
    return [...this.model.tiles].sort((a,b)=>b.h-a.h||(b.x+b.z)-(a.x+a.z)).find(t=>{const p=this.project(t);return Math.abs(x-p.x)/(29*this.scale)+Math.abs(y-p.y)/(14.5*this.scale)<1.04;});
  }
}
