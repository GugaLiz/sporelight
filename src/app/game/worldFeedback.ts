import type { RunState } from './model';

interface Feedback {node:string;kind:'collect'|'grow'|'turn';started:number}
/** Transient feedback only. Saved puzzle progress remains the source of truth. */
export class WorldFeedback {
 private previous?:{collected:string[];activated:string[];vars:Record<string,string>};
 private events:Feedback[]=[];
 update(state:RunState,time:number) {
  const old=this.previous;
  if(old){
   const undone=old.collected.some(id=>!state.collected.includes(id))||old.activated.some(id=>!state.activated.includes(id));
   if(undone)this.events=[];
   else{
    for(const node of state.collected)if(!old.collected.includes(node))this.events.push({node,kind:'collect',started:time});
    for(const node of state.activated)if(!old.activated.includes(node)&&node!=='ritual')this.events.push({node,kind:'grow',started:time});
    for(const [node,value]of Object.entries(state.vars))if(old.vars[node]!==value)this.events.push({node,kind:'turn',started:time});
   }
  }
  this.previous={collected:[...state.collected],activated:[...state.activated],vars:{...state.vars}};
  this.events=this.events.filter(e=>time-e.started<1600).slice(-20);
 }
 emergence(node:string,time:number) {
  const event=this.events.find(e=>e.node===node&&e.kind==='grow');return event?Math.min(1,(time-event.started)/650):1;
 }
 draw(c:CanvasRenderingContext2D,time:number,point:(id:string)=>{x:number;y:number}|undefined,target:{x:number;y:number},scale:number,settings:{particles:boolean;lowMotion:boolean;dynamicLight:boolean}) {
  if(settings.lowMotion)return;
  c.save();
  for(const e of this.events){
   const p=point(e.node);if(!p)continue;const age=time-e.started,q=Math.min(1,age/1250);
   if(e.kind==='collect'){
    if(!settings.particles)continue;
    // Upward curl, then a curved flight toward the actual spore counter.
    const f=Math.max(0,(q-.25)/.75),ease=f*f*(3-2*f),x=p.x+(target.x-p.x)*ease,y=p.y-38*scale+(target.y-p.y+38*scale)*ease-Math.sin(q*Math.PI)*60*scale;
    c.globalAlpha=1-Math.pow(q,6);c.fillStyle='#fff3bf';
    for(let i=0;i<4;i++){c.beginPath();c.arc(x-i*3*scale,y+i*2*scale,(3-i*.5)*scale,0,Math.PI*2);c.fill();}
   }else{
    if(settings.dynamicLight){c.globalAlpha=(1-q)*.65;c.strokeStyle=e.kind==='turn'?'#b7e9e0':'#f1e5b4';c.lineWidth=2*scale;c.beginPath();c.ellipse(p.x,p.y, (18+q*60)*scale,(8+q*24)*scale,0,0,Math.PI*2);c.stroke();}
    if(settings.particles)for(let i=0;i<7;i++){const a=i*2.399;c.globalAlpha=(1-q)*.8;c.fillStyle=i%2?'#d6e6ac':'#ffebbe';c.beginPath();c.ellipse(p.x+Math.cos(a)*q*36*scale,p.y-(15+q*50)*scale+Math.sin(a)*q*15*scale,2*scale,3.5*scale,a,0,Math.PI*2);c.fill();}
   }
  }
  c.restore();
 }
}
