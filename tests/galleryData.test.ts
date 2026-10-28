import test from 'node:test';
import assert from 'node:assert/strict';
import {createDefaultSave} from '../src/app/save';
import {GALLERY_ITEMS,GALLERY_CATEGORIES,galleryUnlocked,galleryMarks,galleryFirstFound,gallerySelection} from '../src/app/scenes/galleryData';
import {renderGalleryDetail} from '../src/app/scenes/galleryScene';
import type {AppState} from '../src/app/types';
const item=(id:string)=>GALLERY_ITEMS.find(i=>i.id===id)!;
test('Journal categories cover eight real entries and a fresh journal reveals none',()=>{
 const save=createDefaultSave();assert.equal(GALLERY_ITEMS.length,8);assert.equal(new Set(GALLERY_ITEMS.map(i=>i.id)).size,8);
 const sizes=GALLERY_CATEGORIES.filter(c=>c!=='全部').map(c=>GALLERY_ITEMS.filter(i=>i.category===c).length);
 assert.equal(sizes.reduce((a,b)=>a+b,0),8);assert.ok(sizes.every(n=>n>0));assert.ok(GALLERY_ITEMS.every(i=>!galleryUnlocked(save,i)&&galleryMarks(save,i)===0));
});
test('Observation marks reflect collected progress and do not grant or alter rewards',()=>{
 const save=createDefaultSave();const data=save.levels['1-1'];data.completed=true;data.bestCollected=1;
 const before=JSON.stringify(save);assert.equal(galleryUnlocked(save,item('flowerbud')),true);assert.equal(galleryMarks(save,item('flowerbud')),2);assert.equal(JSON.stringify(save),before);
 data.bestCollected=2;assert.equal(galleryMarks(save,item('flowerbud')),3);data.bestCollected=3;assert.equal(galleryMarks(save,item('flowerbud')),5);
});
test('Legacy discovery without collection records shows one mark and no invented first level',()=>{
 const save=createDefaultSave();save.gallery.moss=true;assert.equal(galleryMarks(save,item('moss')),1);assert.equal(galleryFirstFound(save,item('moss')),'记于微光旅程');
 save.levels['2-2'].completed=true;save.levels['2-2'].bestCollected=3;assert.match(galleryFirstFound(save,item('moss')),/雨滴池塘 2-2/);
});
test('Changing category repairs an incompatible selection and preserves reading mode',()=>{
 const state:AppState={save:createDefaultSave(),scene:'gallery',settingsOpen:false,confirmMode:null,bootReady:true,galleryCategory:'建筑',gallerySelected:'flowerbud',galleryMode:'story'};
 const selection=gallerySelection(state);assert.equal(selection.selected?.id,'arch');assert.equal(selection.items.length,1);assert.equal(selection.mode,'story');
 state.gallerySelected='missing';assert.equal(gallerySelection(state).selected?.id,'arch');
});
test('Undiscovered story pages contain a finding hint but no story reveal',()=>{
 const html=renderGalleryDetail(item('starflower'),createDefaultSave(),'story');assert.match(html,/尚未发现/);assert.match(html,/3-4/);assert.ok(!html.includes('找回八粒孢子'));assert.ok(!html.includes('journal-story-prose'));
});
test('Story text escapes a custom player name before rendering',()=>{
 const save=createDefaultSave();save.gallery.flowerbud=true;save.playerName='<script>alert(1)</script>';
 const html=renderGalleryDetail(item('flowerbud'),save,'story');assert.ok(html.includes('&lt;script&gt;'));assert.ok(!html.includes('<script>'));
});
