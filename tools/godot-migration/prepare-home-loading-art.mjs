// Package generated, transparent whole poses. No matte extraction/body assembly.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
const require=createRequire(import.meta.url);
let sharp;try{sharp=require('sharp');}catch{sharp=require(join(process.env.USERPROFILE,'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp'));}
const base=resolve('assets/images/home-loading-refine-20261118');
const output=resolve('godot/assets/images/home-loading-refine-20261118');
const bytes=await readFile(join(base,'masters/cover-quarter-walk.png'));
const {data,info}=await sharp(bytes).ensureAlpha().raw().toBuffer({resolveWithObject:true});
const cells=[];
for(let i=0;i<9;i++){
 const left=Math.floor(i%3*info.width/3),top=Math.floor(Math.floor(i/3)*info.height/3);
 const width=Math.floor((i%3+1)*info.width/3)-left,height=Math.floor((Math.floor(i/3)+1)*info.height/3)-top;
 const bounds=[width,height,-1,-1],hat=[width,-1];
 for(let y=0;y<height;y++)for(let x=0;x<width;x++){
  const p=((top+y)*info.width+left+x)*4;
  if(data[p+3]<8)continue;
  bounds[0]=Math.min(bounds[0],x);bounds[1]=Math.min(bounds[1],y);bounds[2]=Math.max(bounds[2],x);bounds[3]=Math.max(bounds[3],y);
  if(y<height*.5&&data[p+3]>=128&&data[p]>data[p+1]*1.3&&data[p]>90){hat[0]=Math.min(hat[0],x);hat[1]=Math.max(hat[1],x);}
 }
 if(bounds[2]<0||hat[1]<hat[0])throw Error('Missing generated pose '+i);
 cells.push({rect:{left,top,width,height},bounds,anchor:[(hat[0]+hat[1])/2,bounds[3]+1]});
}
const median=values=>[...values].sort((a,b)=>a-b)[Math.floor(values.length/2)];
const scale=432/median(cells.map(c=>c.bounds[3]+1-c.bounds[1]));
await mkdir(output,{recursive:true});
const frames=[];
for(let i=0;i<cells.length;i++){
 const cell=cells[i],b=cell.bounds;
 const width=Math.round((b[2]-b[0]+1)*scale),height=Math.round((b[3]-b[1]+1)*scale);
 const left=Math.round(256+(b[0]-cell.anchor[0])*scale),top=472-height;
 if(left<0||top<0||left+width>512||top+height>512)throw Error('Pose exceeds registered canvas '+i);
 const input=await sharp(bytes).extract({left:cell.rect.left+b[0],top:cell.rect.top+b[1],width:b[2]-b[0]+1,height:b[3]-b[1]+1}).resize(width,height).png().toBuffer();
 const name=i===0?'idle-quarter.png':`walk-quarter-${i}.png`;
 const frame=await sharp({create:{width:512,height:512,channels:4,background:{r:0,g:0,b:0,alpha:0}}}).composite([{input,left,top}]).png().toBuffer();
 await writeFile(join(output,name),frame);
 frames.push({name,cell,scale,logicalFoot:[256,472],visibleRect:[left,top,width,height],sha256:createHash('sha256').update(frame).digest('hex')});
}
await writeFile(join(base,'registration.json'),JSON.stringify({master:'masters/cover-quarter-walk.png',masterSha256:createHash('sha256').update(bytes).digest('hex'),masterCanvas:[info.width,info.height],grid:[3,3],method:'One uniform clip scale; whole-pose translation registers cap center and sole baseline, preserves alpha. No per-frame scale fitting or articulated compositing.',frames},null,2)+'\n');
console.log(JSON.stringify({frames:frames.length,scale,output}));
