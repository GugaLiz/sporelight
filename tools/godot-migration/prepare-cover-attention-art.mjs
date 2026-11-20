// Package complete generated gaze/gesture poses; no articulated body pieces.
import {readFile,writeFile,mkdir,copyFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
const require=createRequire(import.meta.url);
const sharp=require(join(process.env.USERPROFILE,'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp'));
const identity=process.argv.includes('--profile=identity');
const corrected=identity||process.argv.includes('--profile=proportions');
const pack=identity?'cover-identity-20261118':(corrected?'cover-proportions-20261118':'cover-attention-20261118');
const base=resolve('assets/images',pack),output=resolve('godot/assets/images',pack);
await mkdir(join(base,'masters'),{recursive:true});await mkdir(output,{recursive:true});
const master=join(base,'masters/attention-sheet.png');
if(process.argv[2])await copyFile(process.argv[2],master);
const bytes=await readFile(master),{data,info}=await sharp(bytes).ensureAlpha().raw().toBuffer({resolveWithObject:true});
if(info.width!==1536||info.height!==1024)throw Error('Unexpected gaze sheet size');
const frames=[];
let scale=.915;
if(corrected){
 const heights=[];
 for(let i=0;i<6;i++){
  let top=512,bottom=-1;
  for(let y=0;y<512;y++)for(let x=0;x<512;x++)if(data[((Math.floor(i/3)*512+y)*info.width+i%3*512+x)*4+3]>=32){top=Math.min(top,y);bottom=Math.max(bottom,y);}
  heights.push(bottom-top+1);
 }
 heights.sort((a,b)=>a-b);
 scale=434/((heights[2]+heights[3])/2);
}
// Source-eye midpoint and neck pivot, measured per full-body illustration.
const eyes=identity?[[238,204],[207,210],[202,232],[238,207],[208,211],[207,208]]:(corrected?[[258,210],[200,225],[173,259],[278,189],[268,183],[214,183]]:[[240,242],[185,258],[165,298],[278,213],[280,201],[219,195]]);
const necks=identity?[[252,270],[223,270],[223,279],[251,278],[224,281],[226,283]]:(corrected?[[265,282],[229,286],[211,305],[279,270],[267,269],[214,269]]:[[250,335],[230,345],[227,360],[277,304],[276,302],[220,304]]);
for(let i=0;i<6;i++){
 const x0=i%3*512,y0=Math.floor(i/3)*512,b=[512,512,-1,-1],boots=[512,-1];
 for(let y=0;y<512;y++)for(let x=0;x<512;x++){
  const p=((y0+y)*info.width+x0+x)*4;if(data[p+3]<16)continue;
  b[0]=Math.min(b[0],x);b[1]=Math.min(b[1],y);b[2]=Math.max(b[2],x);b[3]=Math.max(b[3],y);
  if(y>420&&data[p+3]>128){boots[0]=Math.min(boots[0],x);boots[1]=Math.max(boots[1],x);}
 }
 const root=[(boots[0]+boots[1])/2,b[3]+1];
 const width=Math.round((b[2]-b[0]+1)*scale),height=Math.round((b[3]-b[1]+1)*scale),left=Math.round(256+(b[0]-root[0])*scale),top=472-height;
 if(left<0||top<0||left+width>512)throw Error('Registered gaze pose outside canvas');
 const sprite=await sharp(bytes).extract({left:x0+b[0],top:y0+b[1],width:b[2]-b[0]+1,height:b[3]-b[1]+1}).resize(width,height).png().toBuffer();
 const packed=await sharp({create:{width:512,height:512,channels:4,background:{r:0,g:0,b:0,alpha:0}}}).composite([{input:sprite,left,top}]).png().toBuffer();
 const name=`attention-${i}.png`;await writeFile(join(output,name),packed);
 const register=p=>[Math.round(256+(p[0]-root[0])*scale),Math.round(472+(p[1]-root[1])*scale)];
 frames.push({name,sourceCell:[x0,y0,512,512],sourceBounds:b,sourceRoot:root,scale,foot:[256,472],eyes:register(eyes[i]),neck:register(necks[i]),sha256:createHash('sha256').update(packed).digest('hex')});
}
await writeFile(join(base,'registration.json'),JSON.stringify({master:'masters/attention-sheet.png',masterSha256:createHash('sha256').update(bytes).digest('hex'),canvas:[512,512],method:'Complete generated poses at one scale, boot-center registration and measured eye/neck anchors; source alpha retained.',frames},null,2)+'\n');
console.log(JSON.stringify(frames.map(f=>({name:f.name,eyes:f.eyes,neck:f.neck,root:f.sourceRoot,bounds:f.sourceBounds}))));
