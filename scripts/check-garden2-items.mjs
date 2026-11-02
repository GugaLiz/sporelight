import {createRequire} from 'node:module';
import {build} from 'esbuild';
import {mkdir,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const require=createRequire(import.meta.url),{chromium}=require(process.argv[2]||'playwright');
const bundle=await build({stdin:{contents:"export {GardenWorld} from './src/app/garden2/world';export {GARDEN_SOLUTIONS} from './tests/garden2Solutions';",resolveDir:process.cwd()},bundle:true,platform:'node',format:'esm',write:false});
const {GardenWorld,GARDEN_SOLUTIONS}=await import('data:text/javascript;base64,'+Buffer.from(bundle.outputFiles[0].text).toString('base64'));
const browser=await chromium.launch({channel:'chrome',headless:true}),page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[],checks=[];
page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=400)errors.push(`${r.status()} ${r.url()}`);});
await mkdir('docs/qa-garden2/items',{recursive:true});
const ready=()=>page.waitForFunction(()=>document.querySelector('#gardenCanvas')?.dataset.moving==='false');
const data=key=>page.locator('#gardenCanvas').getAttribute('data-'+key);
const act=async id=>{await page.locator(`#gardenCommands [data-garden-do="${id}"]`).click();await ready();};
const walk=async tile=>{await page.locator(`[data-garden-tile="${tile}"]`).first().click();await page.waitForFunction(tile=>{const d=document.querySelector('#gardenCanvas')?.dataset;return d?.tile===tile&&d.moving==='false';},tile);};
const saved=()=>page.evaluate(()=>{const p=JSON.parse(localStorage.getItem('sporelight.garden2.v1'));return p.runs[p.lastLevel];});
async function shot(name){await page.screenshot({path:`docs/qa-garden2/items/${name}.png`});await page.evaluate(async name=>{const canvas=document.querySelector('#gardenCanvas'),d=canvas.dataset,ratio=canvas.width/canvas.clientWidth,crop=document.createElement('canvas');crop.width=300;crop.height=230;crop.getContext('2d').drawImage(canvas,(+d.characterX-150)*ratio,(+d.characterY-170)*ratio,300*ratio,230*ratio,0,0,300,230);window.itemCrop=crop.toDataURL('image/png');},name);const crop=await page.evaluate(()=>window.itemCrop);await writeFile(`docs/qa-garden2/items/${name}-detail.png`,Buffer.from(crop.split(',')[1],'base64'));}
async function enter(w){await page.evaluate(run=>{localStorage.setItem('sporelight.save.v2',JSON.stringify({hasNamed:true,lastLevel:run.levelId,levels:Object.fromEntries(['1-1','1-2','1-3','1-4','2-1','2-2','2-3','2-4','3-1','3-2'].map(id=>[id,{completed:true}])),settings:{bgm:0,ambient:0,lowMotion:false}}));localStorage.setItem('sporelight.garden2.v1',JSON.stringify({version:1,lastLevel:run.levelId,runs:{[run.levelId]:run},records:{},memories:{}}));},w.snapshot());await page.reload();await page.locator('[data-action="继续旅程"]').click();await ready();await page.waitForLoadState('networkidle');}
try{
 await page.goto('http://127.0.0.1:4173/');const w=new GardenWorld('2-1');for(const tile of w.pathTo('f:-1:4'))w.move(tile);await enter(w);await shot('01-dew-plant');
 await act('take:dew');assert.equal((await saved()).items.dew.picked,true);assert.equal(await data('carried-item'),'dew');assert.equal(await data('carry-style'),'satchel');await shot('02-dew-satchel');
 await page.setViewportSize({width:390,height:844});await shot('03-dew-satchel-phone');await page.setViewportSize({width:1440,height:900});
 await walk('f:-2:4');await shot('04-dew-after-turn');await act('drop:dew:f:-2:4');assert.equal(await data('carried-item'),'');assert.equal((await saved()).items.dew.picked,true);await walk('f:-1:4');await shot('05-dropped-parcel');
 await page.reload();await page.locator('[data-action="继续旅程"]').click();await ready();assert.equal((await saved()).items.dew.picked,true);await act('take:dew');await page.locator('[data-action="撤销"]').click();await ready();assert.equal(await data('carried-item'),'');assert.equal((await saved()).items.dew.tile,'f:-2:4');await act('take:dew');
 await walk('m:float:0:0');await act('use:care');assert.equal(await data('carried-item'),'');assert.equal((await saved()).items.dew.tile,'');await act('valve:water');await walk('f:4:0');await page.locator('[data-action="播种"]').click();await page.waitForFunction(()=>document.querySelector('#gardenCanvas')?.dataset.completed==='true');checks.push('2-1 uses supplied dew plant and leaf parcel artwork; pickup, turn, drop, reload, undo and watering retain the correct form and complete the level');
 const bell=new GardenWorld('1-4');for(const step of GARDEN_SOLUTIONS['1-4']){if(step.startsWith('!'))bell.act(step.slice(1));else for(const tile of bell.pathTo(step))bell.move(tile);if(step==='!take:bell')break;}
 await enter(bell);assert.equal(await data('carried-item'),'bell');await shot('06-bell-satchel');await walk('f:-4:0');await act('use:home');assert.equal(await data('carried-item'),'');await page.locator('[data-action="撤销"]').click();await ready();assert.equal(await data('carried-item'),'bell');assert.ok(!(await saved()).flags.includes('home'));checks.push('1-4 bell sits inside an attached leaf satchel; returning it removes the satchel and undo restores it');
 await page.setViewportSize({width:390,height:844});await shot('07-bell-satchel-phone');assert.deepEqual(errors,[]);await writeFile('docs/qa-garden2/items/checks.json',JSON.stringify({checks,errors},null,2));console.log(JSON.stringify({checks,errors},null,2));
}finally{await browser.close();}
