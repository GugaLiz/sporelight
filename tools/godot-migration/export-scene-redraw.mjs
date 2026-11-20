import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {readFile,writeFile,mkdir,copyFile} from 'node:fs/promises';
import {dirname,join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

// ImageGen draws the art. This tool only registers transparent masters to the
// existing logical canvases and writes lossless PNGs with alpha-aware sampling.
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const option=(key,fallback)=>process.argv.find(value=>value.startsWith('--'+key+'='))?.slice(key.length+3)??fallback;
const require=createRequire(import.meta.url);
let sharp;
try{sharp=require(option('sharp','sharp'));}
catch{
 const bundled=join(process.env.USERPROFILE??process.env.HOME??'','.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
 sharp=require(bundled);
}
const id='scene-redraw-20261116';
const masters=join(root,'assets/images',id,'masters');
const output=join(root,'godot/assets/images',id);
const manifestFile=join(root,'assets/images',id,'manifest.json');
const sourceDirectory=option('from','');
const checkOnly=process.argv.includes('--check');
const selected=new Set(option('only','').split(',').filter(Boolean));
const aliases={
 arch:{source:'grid-world/arch.png',generated:'75b57e9e-fafa-47f3-bd9f-ac2960440c42'},
 'gold-lotus':{source:'garden-scenery/gold-lotus.png',generated:'cfbef614-fb76-4a96-87d1-8947907c38b5'},
 'ivory-lotus':{source:'garden-scenery/ivory-lotus.png',generated:'236f3012-9c91-4c13-a55d-4b4953ac5035'},
 'blue-flowers':{source:'garden-scenery/blue-flowers.png',generated:'b76aea6f-3c33-48a2-b6fb-4e624f8380ee'},
 spore:{source:'material-ready/icon-spore.png',generated:'24281f83-9277-4a5f-a834-88535bdc8117'},
 bloom:{source:'production/bloom.png',generated:'40754e20-9bbd-4ca8-b835-a49a7bbe4828'},
 flower:{source:'production/flower.png',generated:'3ac1564f-d687-4ef9-8e76-8bd6b45bb681'},
};
for(const alias of selected)if(!aliases[alias])throw Error('Unknown redraw alias: '+alias);
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const relative=file=>file.replaceAll('\\','/').slice(root.replaceAll('\\','/').length+1);
async function pixels(file){
 const bytes=await readFile(file);
 const {data,info}=await sharp(bytes).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 return {bytes,data,width:info.width,height:info.height,channels:info.channels};
}
function bounds(image,threshold){
 let x0=image.width,y0=image.height,x1=-1,y1=-1,count=0;
 for(let y=0;y<image.height;y++)for(let x=0;x<image.width;x++){
  if(image.data[(y*image.width+x)*image.channels+3]<threshold)continue;
  count++;x0=Math.min(x0,x);y0=Math.min(y0,y);x1=Math.max(x1,x);y1=Math.max(y1,y);
 }
 return {rect:count?[x0,y0,x1-x0+1,y1-y0+1]:[0,0,0,0],pixels:count};
}
function alphaStats(image){
 let opaque=0,partial=0,clear=0;
 for(let i=3;i<image.data.length;i+=image.channels){const alpha=image.data[i];if(alpha===0)clear++;else if(alpha===255)opaque++;else partial++;}
 return {opaque,partial,clear};
}
function mainOrb(image){
 // Measure the connected gold sphere, excluding the cream rim, soft glow,
 // sprout and separate satellites. The same colour predicate is applied to
 // original, master and exported pixels; glow bounds never set body size.
 const {data,width,height,channels}=image;
 const mask=new Uint8Array(width*height);
 for(let i=0;i<mask.length;i++){
  const offset=i*channels,r=data[offset],g=data[offset+1],b=data[offset+2],a=data[offset+3];
  mask[i]=a>220&&r>180&&g>80&&g<245&&b<180&&r-g>10&&g-b>20?1:0;
 }
 let largest={pixels:0,rect:[0,0,0,0]};
 for(let i=0;i<mask.length;i++){
  if(!mask[i])continue;
  const queue=[i];mask[i]=0;
  let x0=width,y0=height,x1=-1,y1=-1;
  for(let cursor=0;cursor<queue.length;cursor++){
   const pixel=queue[cursor],x=pixel%width,y=Math.floor(pixel/width);
   x0=Math.min(x0,x);y0=Math.min(y0,y);x1=Math.max(x1,x);y1=Math.max(y1,y);
   for(const neighbour of [pixel-1,pixel+1,pixel-width,pixel+width]){
    if(neighbour<0||neighbour>=mask.length||!mask[neighbour]||Math.abs(neighbour%width-x)>1)continue;
    mask[neighbour]=0;queue.push(neighbour);
   }
  }
  if(queue.length>largest.pixels)largest={pixels:queue.length,rect:[x0,y0,x1-x0+1,y1-y0+1]};
 }
 const [x,y,w,h]=largest.rect;
 return {...largest,centre:[x+w*.5,y+h*.5],diameter:Math.max(w,h),aspect:w/h};
}
function mapping(source,target){
 return {crop:source,left:target[0],top:target[1],width:target[2],height:target[3]};
}
function mappedPoint(point,transform){
 return [transform.left+(point[0]-transform.crop[0])*transform.width/transform.crop[2],transform.top+(point[1]-transform.crop[1])*transform.height/transform.crop[3]];
}
const importSettings=`[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=0\nmipmaps/generate=true\nmipmaps/limit=-1\nprocess/fix_alpha_border=true\nprocess/premult_alpha=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n`;

if(checkOnly){
 const manifest=JSON.parse(await readFile(manifestFile,'utf8'));
 const theme=JSON.parse(await readFile(join(root,'godot/content/element-theme.json'),'utf8'));
 for(const entry of manifest.entries){
  const original=await readFile(join(root,entry.original.path));
  const master=await readFile(join(root,entry.master.path));
  const result=await pixels(join(root,entry.output.path));
  if(sha(original)!==entry.original.sha256)throw Error('Original asset differs: '+entry.alias);
  if(sha(master)!==entry.master.sha256||sha(result.bytes)!==entry.output.sha256)throw Error('Redraw provenance differs: '+entry.alias);
  if(theme.resource_overrides[entry.alias]!=='res://'+entry.output.path.replace(/^godot\//,''))throw Error('World theme binding differs: '+entry.alias);
  if(result.width!==entry.original.canvas[0]||result.height!==entry.original.canvas[1])throw Error('Logical canvas differs: '+entry.alias);
  if(JSON.stringify(bounds(result,8))!==JSON.stringify(entry.output.alpha8)||JSON.stringify(bounds(result,128))!==JSON.stringify(entry.output.alpha128))throw Error('Alpha measurement differs: '+entry.alias);
  const config=await readFile(join(root,entry.output.path)+'.import','utf8');
  if(!config.includes('mipmaps/generate=true'))throw Error('Mipmap generation missing: '+entry.alias);
  if(entry.alias==='spore'){
   const body=mainOrb(result),reference=entry.mainOrb.original;
   if(Math.abs(body.aspect-1)>.02||Math.abs(body.diameter-reference.diameter)>2)throw Error('Spore body changed roundness or size');
   if(Math.hypot(body.centre[0]-reference.centre[0],body.centre[1]-reference.centre[1])>1)throw Error('Spore body centre moved');
  }
 }
 console.log('PASS '+manifest.entries.length+' registered redraw assets, master/output hashes, alpha bounds and mipmaps');
 process.exit(0);
}
await mkdir(masters,{recursive:true});
await mkdir(output,{recursive:true});
if(sourceDirectory){
 for(const [alias,spec]of Object.entries(aliases))if(!selected.size||selected.has(alias))await copyFile(join(sourceDirectory,'exec-'+spec.generated+'.png'),join(masters,alias+'.png'));
}
const originals={},inputs={};
for(const [alias,spec]of Object.entries(aliases)){
 originals[alias]=await pixels(join(root,'godot/assets/images',spec.source));
 inputs[alias]=await pixels(join(masters,alias+'.png'));
}
const transforms={};
for(const alias of Object.keys(aliases))transforms[alias]=mapping(bounds(inputs[alias],8).rect,bounds(originals[alias],8).rect);

// The bud was edited from the completed master. Use ONE registration for both
// states so their unchanged stone base never grows, shrinks or moves on repair.
transforms.flower={...transforms.bloom,crop:[...transforms.bloom.crop]};

// The new arch keeps two pillars, ivy and an open doorway. Register the complete
// ground-foot centres, rather than aligning its tall crown's bounding rectangle.
// These are reviewed master-image ground reference points, not foliage bounds.
const archFeet={master:[[390,950],[840,1076]],logical:[[72,188],[164,213]],logicalHalfAxes:[[30,15],[32,16]]};
const archCrop=transforms.arch.crop;
const archScale=[92/(840-390),25/(1076-950)];
transforms.arch={crop:archCrop,
 left:Math.round(72+(archCrop[0]-390)*archScale[0]),top:Math.round(188+(archCrop[1]-950)*archScale[1]),
 width:Math.round(archCrop[2]*archScale[0]),height:Math.round(archCrop[3]*archScale[1])};

// The generated spore has a different satellite/halo arrangement. Filling its
// old overall alpha rectangle stretched the sphere into an ellipse. Register
// the main sphere's diameter/centre with ONE scale in both axes instead.
const orbReference=mainOrb(originals.spore),orbMaster=mainOrb(inputs.spore);
const sporeBounds=bounds(inputs.spore,8).rect;
const sporeSide=Math.max(sporeBounds[2],sporeBounds[3]);
const sporeWidth=Math.round(sporeSide*orbReference.diameter/orbMaster.diameter);
const sporeScale=sporeWidth/sporeSide;
transforms.spore={crop:[sporeBounds[0],sporeBounds[1],sporeSide,sporeSide],
 left:Math.round(orbReference.centre[0]+(sporeBounds[0]-orbMaster.centre[0])*sporeScale),
 top:Math.round(orbReference.centre[1]+(sporeBounds[1]-orbMaster.centre[1])*sporeScale),
 width:sporeWidth,height:sporeWidth};

const entries=[];
for(const [alias,spec]of Object.entries(aliases)){
 if(selected.size&&!selected.has(alias))continue;
 const original=originals[alias],master=inputs[alias],transform=transforms[alias];
 const [left,top,width,height]=transform.crop;
 if(transform.left<0||transform.top<0||transform.left+transform.width>original.width||transform.top+transform.height>original.height)throw Error('Registration exceeds logical canvas: '+alias);
 // Sharp/libvips automatically premultiplies RGBA while resizing, then returns
 // straight alpha. Never threshold alpha, erase speckles, blur or invent pixels.
 const resized=await sharp(master.bytes).ensureAlpha().extract({left,top,width,height})
  .resize(transform.width,transform.height,{fit:'fill',kernel:'lanczos3'}).png().toBuffer();
 const destination=join(output,alias+'.png');
 const bytes=await sharp({create:{width:original.width,height:original.height,channels:4,background:{r:0,g:0,b:0,alpha:0}}})
  .composite([{input:resized,left:transform.left,top:transform.top}]).png({compressionLevel:9}).toBuffer();
 await writeFile(destination,bytes);
 // Preserve Godot's generated remap/uid on later runs; only set the intended
 // import parameters when first creating a new non-destructive sibling asset.
 try{await readFile(destination+'.import');}catch{await writeFile(destination+'.import',importSettings);}
 const result=await pixels(destination);
 entries.push({alias,original:{path:'godot/assets/images/'+spec.source,sha256:sha(original.bytes),canvas:[original.width,original.height],alpha8:bounds(original,8),alpha128:bounds(original,128),alpha:alphaStats(original)},
  master:{path:relative(join(masters,alias+'.png')),sha256:sha(master.bytes),canvas:[master.width,master.height],alpha8:bounds(master,8),alpha128:bounds(master,128),generator:'built-in image_gen',generationId:spec.generated},
  transform:{...transform,method:alias==='spore'?'uniform-scale-main-sphere-registration-premultiplied-lanczos3':'crop-alpha8-and-premultiplied-lanczos3-to-logical-canvas',sharedWith:alias==='flower'?'bloom':null},
  output:{path:relative(destination),sha256:sha(bytes),canvas:[result.width,result.height],alpha8:bounds(result,8),alpha128:bounds(result,128),alpha:alphaStats(result),mipmaps:true},
  ...(alias==='arch'?{archFeet:{...archFeet,mapped:archFeet.master.map(point=>mappedPoint(point,transform)),acceptance:'registration points preserved within 0.3 logical pixels; complete painted plinth and passage require GPU review'}}:{}),
  ...(alias==='spore'?{mainOrb:{original:orbReference,master:orbMaster,output:mainOrb(result),scale:sporeScale,measurement:'Largest connected gold region: alpha>220, r>180, 80<g<245, b<180, r-g>10, g-b>20. Cream outline and halo excluded.'}}:{})});
}
if(selected.size){
 const previous=JSON.parse(await readFile(manifestFile,'utf8'));
 const replacement=new Map(entries.map(entry=>[entry.alias,entry]));
 entries.splice(0,entries.length,...previous.entries.map(entry=>replacement.get(entry.alias)??entry));
}
const manifest={schema_version:1,id,generator:'built-in image_gen',sampling:'sharp '+sharp.versions.sharp+' / libvips '+sharp.versions.vips,
 scope:'Appearance only. Original resources, logical canvases, world scale, anchors, hard bases, collision, topology and save state are retained.',
 notes:['Masters are generated redraws; this exporter performs only lossless packaging, transparent cropping and alpha-aware resampling.','Only the seven world aliases are overridden; UI icon-spore retains its original alias.','Flower and bloom share the same master-to-canvas transform and painted stone-base registration.','Arch complete pillar-foot reference points are registered to the existing canonical hard-base coordinates. GPU verification remains required.','Spore uses one uniform scale, measured from the main gold sphere rather than its old white-rim/halo bounds; its original sphere diameter and centre are retained.','Fractional alpha is preserved. Mipmaps are generated for all new world sprites; opaque prepass and depth testing remain unchanged.'],entries};
await writeFile(manifestFile,JSON.stringify(manifest,null,2)+'\n');
const themeFile=join(root,'godot/content/element-theme.json');
const theme=JSON.parse(await readFile(themeFile,'utf8'));
for(const alias of Object.keys(aliases))theme.resource_overrides[alias]='res://assets/images/'+id+'/'+alias+'.png';
theme.id=id;
await writeFile(themeFile,JSON.stringify(theme,null,2)+'\n');
console.log('Exported '+entries.length+' redraws to '+relative(output)+'; original dimensions and canonical registration retained.');
