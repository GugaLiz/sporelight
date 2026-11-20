import sharp from 'file:///C:/Users/liuli/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp/dist/index.cjs';
import {readdir} from 'node:fs/promises';
const dir='G:/works/liuli/sporelight/docs/qa-godot-native/game-hud-feedback-20261118/gpu-delivery';
const files=(await readdir(dir)).filter(f=> /-(initial|overview-phase2)-1280x720.png$/.test(f)).sort();
for(let n=0;n<files.length;n+=6){
 const composites=[];
 for(let i=n;i<Math.min(n+6,files.length);i++){
  const index=i-n, x=index%2*640, y=Math.floor(index/2)*390;
  composites.push({input:await sharp(dir+'/'+files[i]).resize(640,360).toBuffer(),left:x,top:y+30});
  composites.push({input:Buffer.from('<svg width="640" height="30"><text x="8" y="22" fill="white" font-family="sans-serif" font-size="19">'+files[i]+'</text></svg>'),left:x,top:y});
 }
 await sharp({create:{width:1280,height:1170,channels:4,background:'#30352b'}}).composite(composites).png().toFile(dir+'/review-'+(n/6+1)+'.png');
}
