import{createRequire}from'node:module';
import{readFile,writeFile,mkdir}from'node:fs/promises';
import{resolve,dirname,relative,sep}from'node:path';
import{fileURLToPath}from'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const option=(key,fallback)=>process.argv.find(v=>v.startsWith('--'+key+'='))?.slice(key.length+3)??fallback;
const sharp=createRequire(import.meta.url)(option('sharp',resolve(process.env.USERPROFILE??process.env.HOME??'','.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp')));
const manifestFile=resolve(root,option('manifest','assets/images/full-asset-redraw-20261116/manifest.json'));
const output=resolve(root,option('output','docs/qa-godot-native/full-asset-redraw-20261116/contacts'));
const count=Number(option('rows','6'));
if(!Number.isInteger(count)||count<1||count>12)throw Error('rows must be 1..12');
const rel=relative(root,output);if(rel==='..'||rel.startsWith('..'+sep)||/^[a-z]:/i.test(rel))throw Error('Contact output must stay in workspace');
const manifest=JSON.parse(await readFile(manifestFile,'utf8'));
const selected=new Set(option('only','').split(',').filter(Boolean));
const entries=manifest.entries.filter(e=>!selected.size||selected.has(e.id));
const escape=value=>String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
await mkdir(output,{recursive:true});
const pages=[];
for(let start=0;start<entries.length;start+=count){
 const rows=entries.slice(start,start+count),cell=Math.max(220,...rows.map(e=>e.original.canvas[0]+30));
 const heights=rows.map(e=>Math.max(180,e.original.canvas[1]+75)),width=cell*4,height=45+heights.reduce((a,b)=>a+b,0);
 const pieces=[],positions=[];let top=45;
 for(let i=0;i<rows.length;i++){
  const e=rows[i],[w,h]=e.original.canvas;positions.push(top);
  for(let col=0;col<4;col++){
   const plate=await sharp({create:{width:cell,height:heights[i],channels:4,background:col<2?'#eadbb5':'#253b3b'}}).png().toBuffer();
   pieces.push({input:plate,left:col*cell,top});
   pieces.push({input:await readFile(resolve(root,col%2?e.output.path:e.original.path)),left:col*cell+Math.round((cell-w)/2),top:top+48});
  }
  top+=heights[i];
 }
 let svg='<svg xmlns="http://www.w3.org/2000/svg" width="'+width+'" height="'+height+'">';
 for(const[col,label]of['original / warm','redraw / warm','original / dark','redraw / dark'].entries())svg+='<text x="'+(col*cell+12)+'" y="27" font-family="Arial" font-size="15" fill="#233">'+label+'</text>';
 for(let i=0;i<rows.length;i++){
  const e=rows[i],ratio=e.output.alpha8.rect[3]/e.original.alpha8.rect[3];
  const detail='1:1 pixels; height '+(ratio*100).toFixed(1)+'%'+(e.transform.anchor?' / foot error '+e.transform.anchor.error.toFixed(2)+'px':'');
  for(let col=0;col<4;col++){
   const color=col<2?'#342d21':'#f3e6ca';
   svg+='<text x="'+(col*cell+12)+'" y="'+(positions[i]+18)+'" font-family="Arial" font-size="13" fill="'+color+'">'+escape(e.id)+'</text>';
   svg+='<text x="'+(col*cell+12)+'" y="'+(positions[i]+35)+'" font-family="Arial" font-size="10" fill="'+color+'">'+escape(detail)+'</text>';
  }
 }
 svg+='</svg>';pieces.push({input:Buffer.from(svg),left:0,top:0});
 const name='contact-'+String(pages.length+1).padStart(2,'0')+'.png';
 await sharp({create:{width,height,channels:4,background:'#f6eedb'}}).composite(pieces).png().toFile(resolve(output,name));
 pages.push({file:name,entries:rows.map(e=>e.id),canvas:[width,height],pixelScale:1});
}
await writeFile(resolve(output,'index.json'),JSON.stringify({scope:'Unscaled logical PNG pixels on warm/dark plates; this is an alpha/registration review artifact, not actual GPU scene acceptance.',manifest:relative(root,manifestFile).split(sep).join('/'),pages},null,2)+'\n');
console.log(JSON.stringify({pages:pages.length,entries:entries.length,output:relative(root,output).split(sep).join('/')}));
