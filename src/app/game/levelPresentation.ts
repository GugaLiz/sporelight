import type { GameModel } from './model';

// Presentation follows the original story while the current spatial puzzles stay authoritative.
export const LEVEL_PRESENTATION: Record<string, { mood:string; moment:string }> = {
 '1-1':{mood:'晨雾里的第一束光',moment:'沿着微光出发，远处的花苞正轻轻呼吸。'},
 '1-2':{mood:'一粒种子的两次相遇',moment:'枯土长出花瓣；回收的种子，还能为另一处带来春天。'},
 '1-3':{mood:'向高处生长的绿意',moment:'藤蔓转向不同的山台，叶印记住每一次往返。'},
 '1-4':{mood:'鼹鼠家的小小访客',moment:'蝴蝶来到蜜源花旁，害羞的鼹鼠也探出了头。'},
 '2-1':{mood:'睡莲托起一滴快乐',moment:'水面泛起涟漪，张开的睡莲等你选好落点。'},
 '2-2':{mood:'把一束光送进静水',moment:'叶片接力传递微光，水晶回应时，暗处的苔藓也会亮起。'},
 '2-3':{mood:'听见雨滴的回声',moment:'亮起的水纹是雨滴琴的节拍；不用着急，下一轮还会再来。'},
 '2-4':{mood:'萤火守护的归途',moment:'小苔灵守住踏板，萤火虫在高处等候花园重新打开。'},
 '3-1':{mood:'一盏灯，一小片星空',moment:'苔灯亮起，光虫便聚拢过来，陪你看清雾中的路。'},
 '3-2':{mood:'光有两种温柔的形状',moment:'日光与月光投出不同的影桥，走过的碎片会留下回应。'},
 '3-3':{mood:'让水、藤蔓与睡莲相遇',moment:'水流去哪里，哪里就恢复生机；每种生命都有自己的位置。'},
 '3-4':{mood:'把星空还给守护者',moment:'八粒微光、四处星座；每一道回应，都让缠绕的藤蔓松开一层。'},
};

interface Point {x:number;y:number}
interface PresentationOptions {time:number;scale:number;particles:boolean;dynamicLight:boolean;lowMotion:boolean}

/** Draw in world space, below the actors. No decorations become clickable terrain. */
export function drawLevelPresentation(c:CanvasRenderingContext2D,model:GameModel,point:(id:string)=>Point,o:PresentationOptions) {
 const {level,state}=model,{scale:s,particles,dynamicLight}=o,t=o.lowMotion?0:o.time;
 const ring=(p:Point,r:number,color:string)=>{c.strokeStyle=color;c.lineWidth=1.5*s;c.beginPath();c.ellipse(p.x,p.y+6*s,r*s,r*.4*s,0,0,Math.PI*2);c.stroke();};
 const glow=(p:Point,r:number,color:string)=>{if(!dynamicLight)return;const g=c.createRadialGradient(p.x,p.y,0,p.x,p.y,r*s);g.addColorStop(0,color);g.addColorStop(1,'#b5ecde00');c.fillStyle=g;c.fillRect(p.x-r*s,p.y-r*s,r*s*2,r*s*2);};
 const dot=(x:number,y:number,r:number,color:string)=>{c.fillStyle=color;c.beginPath();c.arc(x,y,r*s,0,Math.PI*2);c.fill();};
 const flies=(p:Point,count:number,color:string)=>{if(!particles)return;for(let i=0;i<count;i++){const a=t/1900+i*2.4;dot(p.x+Math.cos(a)*(24+i*5)*s,p.y-24*s+Math.sin(a*1.3+i)*15*s,2,color);}};
 const petals=(p:Point,color:string,count=6)=>{c.fillStyle=color;for(let i=0;i<count;i++){const a=i*Math.PI*2/count;c.beginPath();c.ellipse(p.x+Math.cos(a)*22*s,p.y+Math.sin(a)*9*s,12*s,5*s,a*.3,0,Math.PI*2);c.fill();}};
 const butterfly=(p:Point)=>{const x=p.x+Math.cos(t/1700)*23*s,y=p.y-46*s+Math.sin(t/900)*7*s;c.fillStyle='#f3d9ad';for(const side of [-1,1]){c.beginPath();c.ellipse(x+side*6*s,y,Math.max(2,6+Math.sin(t/120)*3)*s,8*s,side*.4,0,Math.PI*2);c.fill();}dot(x,y,2,'#84664a');};
 c.save();
 // Closed buds remain visible goals; chapter colours connect each to its environment.
 const end=point(level.exit);
 if(model.isVisible(level.exit)){
  glow({x:end.x,y:end.y-32*s},65,level.chapter==='cave'?'#c9bdf24d':'#fff2c845');
  ring(end,38+Math.sin(t/1000)*2,'#e9e1b77a');
 }
 switch(level.id){
  case '1-1': {
   // Tiny ground lights teach movement without drawing a false bridge across gaps.
   const a=point('start'),b=point('fork');
   for(let i=1;i<=5;i++){const q=i/6;dot(a.x+(b.x-a.x)*q,a.y+(b.y-a.y)*q,2,'#fff0ba');}
   petals(point('fern'),'#bdca9277');flies(point('stone'),3,'#f5e6b7');break;
  }
  case '1-2':
   for(const id of ['north','east']){const p=point(id),open=state.activated.includes(id);ring(p,36,open?'#dce8a8':'#ba967a');if(open){petals(p,'#eed5a8b3');flies(p,3,'#fff0b5');}else{c.strokeStyle='#b49170';c.beginPath();c.moveTo(p.x-11*s,p.y);c.lineTo(p.x,p.y+5*s);c.lineTo(p.x+8*s,p.y-3*s);c.stroke();}}
   break;
  case '1-3': {
   const p=point('pivot');petals(p,'#95b479aa');
   for(const id of ['dew','leaf'])if(state.collected.includes(id))petals(point(id),'#dcebb88c',4);
   flies(p,3,'#e2ecae');break;
  }
  case '1-4': {
   const p=point('home'),opened=state.activated.includes('garden');
   // The mole watches from its burrow; the butterfly moves to the opened garden.
   c.fillStyle='#625c49';c.beginPath();c.ellipse(p.x+40*s,p.y+7*s,23*s,10*s,0,0,Math.PI*2);c.fill();
   c.fillStyle='#a18b75';c.beginPath();c.ellipse(p.x+40*s,p.y-3*s,15*s,16*s,0,Math.PI,Math.PI*2);c.fill();
   dot(p.x+35*s,p.y-9*s,1.6,'#343d38');dot(p.x+45*s,p.y-9*s,1.6,'#343d38');dot(p.x+40*s,p.y-3*s,3,'#ddbaa1');
   petals(point(opened?'garden':'near'),'#eed4a6');butterfly(point(opened?'garden':'home'));break;
  }
  case '2-1':
   for(const id of ['upper','west','east']){const p=point(id);for(let i=0;i<2;i++)ring(p,30+((t/65+i*18)%36),'#bbe8e26b');petals(p,'#d4dcb884',5);}break;
  case '2-2': {
   const p=point('pool');for(let i=0;i<3;i++)ring(p,24+i*13,'#b5dedc85');
   const crystal=point('crystal');if(model.beamConnected){glow(crystal,100,'#c0f2cf66');petals(crystal,'#b6e6cfa6');flies(crystal,6,'#fff0ba');}break;
  }
  case '2-3': {
   const p=point('drum'),ready=o.lowMotion||o.time%2400<1200||state.activated.includes('drum');
   ring(p,48,ready?'#bcefe7':'#899fa25c');
   for(let i=0;i<4;i++){const a=-Math.PI/2+i*Math.PI/2;dot(p.x+Math.cos(a)*38*s,p.y+Math.sin(a)*16*s,4,i<state.tune?'#fff0b5':'#8da6a1');}
   if(particles)for(const id of ['echo','drum','lift']){const q=point(id);for(let i=0;i<4;i++){const f=(t/900+i*.27)%1;c.strokeStyle='#cdeae895';c.beginPath();c.moveTo(q.x+(i-2)*16*s,q.y-(65-f*65)*s);c.lineTo(q.x+(i-2)*16*s-3*s,q.y-(57-f*65)*s);c.stroke();}}
   break;
  }
  case '2-4': {
   const open=state.activated.includes('bell');flies(point(open?'home':'bell'),open?9:4,'#fff2a6');
   petals(point('reed'),'#a7bd88b3');if(open)petals(point('home'),'#e8ddb3');break;
  }
  case '3-1':
   for(const id of ['lampA','lampB','lampC'])if(state.activated.includes(id)){const p=point(id);glow(p,140,'#a8edcc55');flies(p,5,'#b8f0ce');ring(p,49,'#b2e3ce65');}break;
  case '3-2': {
   const moon=state.vars.dial==='moon',p=point('dial');
   glow(p,95,moon?'#adc7f755':'#ffe1a955');ring(p,45,moon?'#c4d1f2':'#eed5a3');
   c.fillStyle=moon?'#b6c7e8':'#e2bd7d';c.font=`${25*s}px Georgia`;c.textAlign='center';c.fillText(moon?'☾':'☀',p.x,p.y-52*s);
   for(const id of ['sun','moon'])if(state.collected.includes(id))ring(point(id),29,id==='sun'?'#eed5a3':'#c4d1f2');break;
  }
  case '3-3': {
   const target=state.vars.pump;if(target){const a=point('pump'),b=point(target);c.strokeStyle='#a7dedb';c.lineWidth=2*s;c.setLineDash([4*s,7*s]);c.lineDashOffset=-t/100*s;c.beginPath();c.moveTo(a.x,a.y+8*s);c.quadraticCurveTo(a.x,b.y,b.x,b.y+8*s);c.stroke();c.setLineDash([]);petals(b,'#bedbb69c');glow(b,80,'#a9dfc23b');}break;
  }
  case '3-4': {
   const sequence=level.sequence!,count=sequence.filter(id=>state.activated.includes(id)).length;
   // Four layers release one by one, directly reflecting saved ritual progress.
   for(let i=count;i<4;i++){c.strokeStyle=i%2?'#8c9d83':'#687f71';c.lineWidth=4*s;c.beginPath();c.ellipse(end.x,end.y-(23+i*9)*s,(30+i*4)*s,10*s,-.25+i*.17,0,Math.PI*2);c.stroke();}
   sequence.forEach((id,i)=>{const p=point(id),on=state.activated.includes(id);ring(p,37,on?'#e9dcab':'#99a9b16b');c.fillStyle=on?'#f3e4ae':'#a6bbc1';c.font=`${16*s}px Georgia`;c.textAlign='center';c.fillText(['❧','♢','✦','☾'][i],p.x,p.y-52*s);
    if(on){c.strokeStyle='#c9edd794';c.lineWidth=2*s;c.beginPath();c.moveTo(p.x,p.y-30*s);c.quadraticCurveTo(p.x,end.y-110*s,end.x,end.y-50*s);c.stroke();flies(p,3,'#e0f1be');}
    // Petal lights repeat the star chart without requiring reading a paragraph.
    const a=i*Math.PI/2-Math.PI/2;dot(end.x+Math.cos(a)*48*s,end.y-37*s+Math.sin(a)*22*s,5,on||Math.floor(t/800)%4===i?'#f8ebbd':'#889f9f');
   });
   if(count===4){glow({x:end.x,y:end.y-50*s},180,'#e1eed981');petals(end,'#d2d8efb3',8);flies(end,12,'#fff0c1');butterfly(end);}break;
  }
 }
 c.restore();
}
