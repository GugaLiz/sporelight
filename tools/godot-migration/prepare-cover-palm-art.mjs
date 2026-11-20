// Register complete generated poses; retain source alpha and one shared scale.
import {readFile,writeFile,mkdir,copyFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {resolve,join} from 'node:path';
const require=createRequire(import.meta.url);
const sharp=require(join(process.env.USERPROFILE,'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp'));
const base=resolve('assets/images/cover-palm-20261118'),out=resolve('godot/assets/images/cover-palm-20261118');
await mkdir(join(base,'masters'),{recursive:true});await mkdir(out,{recursive:true});
const master=join(base,'masters/crouch-palm-sheet.png');
if(process.argv[2])await copyFile(process.argv[2],master);
const bytes=await readFile(master),{data,info}=await sharp(bytes).ensureAlpha().raw().toBuffer({resolveWithObject:true});
if(info.width!==1536||info.height!==1024)throw Error('Unexpected sheet dimensions');
const palms=[[247,397],[193,388],[142,371],[187,334],[164,332],[137,332]];
const cells=[];
for(let i=0;i<6;i++){
 const left=i%3*512,top=Math.floor(i/3)*512,b=[512,512,-1,-1],hat=[512,-1];
 for(let y=0;y<512;y++)for(let x=0;x<512;x++){
  const p=((top+y)*info.width+left+x)*4;if(data[p+3]<16)continue;
  b[0]=Math.min(b[0],x);b[1]=Math.min(b[1],y);b[2]=Math.max(b[2],x);b[3]=Math.max(b[3],y);
  if(y<250&&data[p+3]>128&&data[p]>data[p+1]*1.3&&data[p]>90){hat[0]=Math.min(hat[0],x);hat[1]=Math.max(hat[1],x);}
 }
 cells.push({left,top,b,root:[(hat[0]+hat[1])/2,b[3]+1]});
}
const scale=.94,frames=[];
for(let i=0;i<6;i++){
 const c=cells[i],b=c.b,width=Math.round((b[2]-b[0]+1)*scale),height=Math.round((b[3]-b[1]+1)*scale);
 const left=Math.round(256+(b[0]-c.root[0])*scale),top=472-height;
 const sprite=await sharp(bytes).extract({left:c.left+b[0],top:c.top+b[1],width:b[2]-b[0]+1,height:b[3]-b[1]+1}).resize(width,height).png().toBuffer();
 if(left<0||top<0||left+width>512)throw Error('Registered pose outside canvas');
 const output=await sharp({create:{width:512,height:512,channels:4,background:{r:0,g:0,b:0,alpha:0}}}).composite([{input:sprite,left,top}]).png().toBuffer();
 const name=`palm-${i}.png`;await writeFile(join(out,name),output);
 const palm=[Math.round(256+(palms[i][0]-c.root[0])*scale),Math.round(472+(palms[i][1]-c.root[1])*scale)];
 frames.push({name,sourceCell:[c.left,c.top,512,512],visibleBounds:b,sourceRoot:c.root,scale,foot:[256,472],palm,sha256:createHash('sha256').update(output).digest('hex')});
}
await writeFile(join(base,'registration.json'),JSON.stringify({master:'masters/crouch-palm-sheet.png',masterSha256:createHash('sha256').update(bytes).digest('hex'),canvas:[512,512],method:'Whole generated poses; one uniform scale, cap center/boot registration, manually measured palm anchors. Alpha preserved.',frames},null,2)+'\n');
console.log(JSON.stringify(frames.map(f=>({name:f.name,palm:f.palm,bounds:f.visibleBounds}))));
