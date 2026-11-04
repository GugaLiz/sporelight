import {build} from 'esbuild';
import {createRequire} from 'node:module';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const option=(name,fallback)=>process.argv.find(v=>v.startsWith('--'+name+'='))?.slice(name.length+3)??fallback;
const base=option('url','http://localhost:4174');
const output=resolve(root,option('output','docs/qa-godot-migration/reference'));
const require=createRequire(import.meta.url);
const bundled=join(process.env.USERPROFILE??'', '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const {chromium}=require(option('playwright',bundled));
const fixture=JSON.parse(await readFile(resolve(root,'godot/tests/fixtures/reference.json'),'utf8'));
const html=await readFile(resolve(root,'dist/index.html'),'utf8');
const css=html.match(/href="\.\/(assets\/[^"]+\.css)"/)?.[1];
assert.ok(css,'Build stylesheet must be available for the original reference renderer');
const bundle=await build({stdin:{contents:"export {GardenGame} from './src/app/garden2/GardenGame'; export {renderGardenScene} from './src/app/garden2/scene';",resolveDir:root},bundle:true,platform:'browser',format:'iife',globalName:'SporelightReference',define:{'import.meta.env.BASE_URL':JSON.stringify('/')},write:false});
const browser=await chromium.launch({channel:'chrome',headless:true});
const page=await browser.newPage({viewport:{width:1280,height:720},deviceScaleFactor:1});
const errors=[];
const captures=[];
page.on('pageerror',error=>errors.push(error.message));
await mkdir(output,{recursive:true});
try{
 await page.route('**/__godot_reference__',route=>route.fulfill({contentType:'text/html',body:'<!doctype html><html lang="zh-CN"><head><meta charset="UTF-8"><link rel="stylesheet" href="/'+css+'"></head><body><div id="app"></div></body></html>'}));
 await page.goto(base+'/__godot_reference__',{waitUntil:'networkidle'});
 await page.addScriptTag({content:bundle.outputFiles[0].text});
 const settings={bgm:0,sfx:0,ambient:0,quality:'standard',dynamicLight:true,particles:true,lowMotion:false,vibration:false,fullscreen:false,language:'zh-CN'};
 for(const scenario of fixture.cases.filter(c=>c.name.startsWith('authored/'))){
  const middle=scenario.steps.find(step=>step.command.kind==='act'&&step.command.value!=='switch'&&!step.snapshot.completed)??scenario.steps[Math.floor(scenario.steps.length/2)];
  const states=[['arrival',scenario.initial.snapshot],['mechanism',middle.snapshot],['restored',scenario.steps.at(-1).snapshot]];
  for(const [stage,snapshot] of states){
   const actual=await page.evaluate(async({id,snapshot,settings})=>{
    document.querySelector('#app').innerHTML=SporelightReference.renderGardenScene({});
    const game=new SporelightReference.GardenGame(document.querySelector('#gardenCanvas'),id,snapshot,settings,()=>{},()=>{},()=>{});
    game.destroy();
    await Promise.all([...game.renderer.images.values()].map(im=>im.complete?Promise.resolve():new Promise((resolve,reject)=>{im.addEventListener('load',resolve,{once:true});im.addEventListener('error',()=>reject(Error('Image failed: '+im.src)),{once:true});})));
    await document.fonts.ready;
    game.renderer.resize();
    game.renderer.draw(1200,undefined,false);
    const imageErrors=[...game.renderer.images].filter(([,image])=>!image.naturalWidth).map(([alias])=>alias);
    return {snapshot:game.model.snapshot(),imageErrors,scale:game.renderer.scale,origin:[game.renderer.ox,game.renderer.oy]};
   },{id:scenario.levelId,snapshot,settings});
   assert.deepEqual(actual.snapshot,snapshot,'Reference drawing must preserve the source snapshot');
   assert.deepEqual(actual.imageErrors,[]);
   const filename=scenario.levelId+'-'+stage+'.png';
   await page.screenshot({path:join(output,filename),animations:'disabled'});
   const sha256=createHash('sha256').update(await readFile(join(output,filename))).digest('hex');
   captures.push({levelId:scenario.levelId,stage,file:filename,sha256,visualTimeMs:1200,viewport:[1280,720],deviceScaleFactor:1,...actual});
  }
 }
 assert.deepEqual(errors,[]);
 await writeFile(join(output,'manifest.json'),JSON.stringify({format:'sporelight.visual-reference',version:1,referenceCommit:fixture.referenceCommit,renderer:'original-typescript-canvas',baseURL:base,settings,captures,errors},null,2)+'\n');
 console.log(JSON.stringify({captures:captures.length,output,errors}));
}finally{await browser.close();}
