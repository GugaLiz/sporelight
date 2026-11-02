import {GardenWorld} from './world';
import {GARDEN_LEVELS} from './levels';
import type {GardenState} from './types';
import type {SaveData} from '../types';
export const GARDEN_KEY='sporelight.garden2.v1';
export interface GardenProgress{version:1;lastLevel:string;runs:Record<string,GardenState>;memories:Record<string,GardenState>;records:Record<string,{completed:boolean;stars:number;collected:number}>;legacy?:unknown}
export const emptyProgress=():GardenProgress=>({version:1,lastLevel:'1-1',runs:{},memories:{},records:{}});
export function normalizeGardenProgress(raw:unknown){
 const out=emptyProgress();if(!raw||typeof raw!=='object')return out;const p=raw as Partial<GardenProgress>;
 if(p.version!==1)return out;
 if(GARDEN_LEVELS.some(l=>l.id===p.lastLevel))out.lastLevel=p.lastLevel!;
 out.legacy=p.legacy;
 for(const l of GARDEN_LEVELS){
  if(p.runs?.[l.id]?.designVersion===2&&p.runs[l.id].levelId===l.id)out.runs[l.id]=new GardenWorld(l.id,p.runs[l.id]).snapshot();
  const memory=p.memories?.[l.id]??p.runs?.[l.id];if(memory?.completed&&memory.designVersion===2&&memory.levelId===l.id){const restored=new GardenWorld(l.id,memory).snapshot();if(restored.completed)out.memories[l.id]=restored;}
  const r=p.records?.[l.id];if(r&&typeof r==='object')out.records[l.id]={completed:r.completed===true,stars:Math.min(3,Math.max(0,Number.isFinite(r.stars)?Math.floor(r.stars):0)),collected:Math.min(l.total,Math.max(0,Number.isFinite(r.collected)?Math.floor(r.collected):0))};
 }return out;
}
export function loadGardenProgress(){try{return normalizeGardenProgress(JSON.parse(localStorage.getItem(GARDEN_KEY)??'null'));}catch{return emptyProgress();}}
export function persistGardenProgress(p:GardenProgress){try{localStorage.setItem(GARDEN_KEY,JSON.stringify(p));return true;}catch{return false;}}
export function importLegacyGardenRecords(progress:GardenProgress,save:SaveData){
 let changed=false;
 if(!progress.legacy){progress.legacy=JSON.parse(JSON.stringify(save));changed=true;}
 const legacy=progress.legacy as Partial<SaveData>|undefined;
 for(const level of GARDEN_LEVELS){
  const old=legacy?.levels?.[level.id],record=progress.records[level.id];
  if(old?.completed&&!record?.completed){
   progress.records[level.id]={completed:true,stars:Math.max(0,Math.min(3,old.bestStars)),collected:Math.max(0,Math.min(level.total,old.bestCollected))};changed=true;
  }
 }
 if(!Object.keys(progress.runs).length&&legacy&&GARDEN_LEVELS.some(level=>level.id===legacy.lastLevel)){progress.lastLevel=legacy.lastLevel!;changed=true;}
 return changed;
}
