import { materialIcon } from '../ui';
import type { AppState } from '../types';
import { CHAPTERS, LEVELS, totalSpores } from '../game/levels';
import { mapPresentation, MAP_TERRACES, plantImage, lockIcon, sporeIcon } from './mapPresentation';

function particles() {
  return Array.from({length:20},(_,i)=>`<i style="--x:${(i*137+42)%1170}px;--y:${(i*79+160)%570}px;--delay:${-i*.7}s;--size:${i%3+2}px"></i>`).join('');
}

export function renderLevelSelectScene(state: AppState) {
  const {chapter,levels,selected} = mapPresentation(state);
  const selectedSave = state.save.levels[selected.id];
  const chapterCollected = levels.reduce((sum,l)=>sum+state.save.levels[l.id].bestCollected,0);
  const chapterTotal = levels.reduce((sum,l)=>sum+totalSpores(l),0);
  const totalCollected = LEVELS.reduce((sum,l)=>sum+state.save.levels[l.id].bestCollected,0);
  const completed = levels.filter(l=>state.save.levels[l.id].completed).length;
  const nextChapters = CHAPTERS.filter(c=>c.id!==chapter.id);
  const currentIndex = levels.indexOf(selected);
  return `<div class="screen illustrated-map map-theme-${chapter.id}" style="background-image:url('./images/reference-scenes/map-${chapter.id}.jpg')">
    <div class="map-color-haze" aria-hidden="true"></div>
    <header class="illustrated-map-header"><button class="map-back-button" data-action="返回主菜单" aria-label="返回主菜单">${materialIcon('back')}<small>返回</small></button><div class="map-brand" aria-label="微光苔原 Sporelight"><span aria-hidden="true">❧</span><div><h1>微光苔原</h1><p>Sporelight</p></div><span aria-hidden="true">❧</span></div><div class="map-spore-purse" aria-label="旅程累计收集 ${totalCollected} 粒孢子">${sporeIcon}<b>${totalCollected}</b><small>旅程微光</small></div></header>
    <div class="illustrated-map-title"><span>第 ${CHAPTERS.findIndex(c=>c.id===chapter.id)+1} 章</span><h2>${chapter.title}</h2><p>${chapter.description}</p></div>
    <svg class="terrace-path" viewBox="0 0 1280 720" aria-hidden="true"><defs><filter id="pathGlow"><feGaussianBlur stdDeviation="3"/></filter></defs><path class="terrace-path-light" d="M112 441 Q176 411 260 390 Q315 447 400 477 Q470 511 561 485 Q625 467 704 465 Q675 396 709 320 Q734 251 799 201"/><path class="terrace-path-dots" d="M112 441 Q176 411 260 390 Q315 447 400 477 Q470 511 561 485 Q625 467 704 465 Q675 396 709 320 Q734 251 799 201"/></svg>
    <div class="terrace-wild-moss" aria-hidden="true"><img src="./images/reference-scenes/terrain-steps.png" style="left:357px;top:486px;width:88px" alt=""/><img src="./images/reference-scenes/terrain-steps.png" style="left:309px;top:302px;width:83px" alt=""/><img src="./images/reference-scenes/terrain-steps.png" style="left:668px;top:464px;width:86px" alt=""/><img src="./images/reference-scenes/terrain-steps.png" style="left:667px;top:317px;width:85px" alt=""/><img src="./images/reference-scenes/terrain-steps.png" style="left:838px;top:160px;width:82px" alt=""/><img src="./images/production/light.png" style="left:670px;top:406px;width:78px" alt=""/><img src="./images/production/moss.png" style="left:675px;top:264px;width:73px" alt=""/><img src="./images/production/moss.png" style="left:847px;top:112px;width:66px" alt=""/></div>
    <nav class="plant-level-map" aria-label="${chapter.title}的四个关卡">${levels.map((level,i)=>{
      const data=state.save.levels[level.id];const chosen=selected.id===level.id;const pos=MAP_TERRACES[i];
      const status=data.completed?'已通关':data.unlocked?'可以进入':'尚未解锁';
      return `<button class="plant-marker ${data.completed?'is-blooming':data.unlocked?'is-budding':'is-dormant'} ${chosen?'is-chosen':''}" style="left:${pos.x}px;top:${pos.y}px" data-map-level="${level.id}" aria-label="${level.id} ${level.title}，${status}" aria-pressed="${chosen}"><span class="plant-ground-halo" aria-hidden="true"></span><img class="plant-marker-art" src="${plantImage(chapter.id,data.completed,data.unlocked)}" alt="${data.completed?'盛开的花朵':data.unlocked?'待放的花苞':'休眠花床'}"/>${!data.unlocked?`<span class="plant-marker-lock">${lockIcon}</span>`:''}<span class="plant-number">${level.id}${data.completed?'<i>✓</i>':''}</span><span class="plant-tooltip">${level.title}<small>${status}</small></span>${chosen&&data.unlocked?`<img class="map-traveler" src="./images/material-ready/idle-front.png" alt="露薇所在的关卡"/>`:''}</button>`;
    }).join('')}</nav>
    <aside class="illustrated-level-panel" aria-labelledby="mapSelectedTitle"><span class="map-panel-eyebrow">${selectedSave.completed?'已唤醒的微光':selectedSave.unlocked?'下一段旅程':'沉睡中的微光'}</span><h2>${chapter.title}</h2><div class="panel-vine" aria-hidden="true">❧ <i></i> ❧</div><h3 id="mapSelectedTitle">${selected.id} · ${selected.title}</h3><p class="map-mechanic">${selected.kind}</p><div class="illustrated-collection"><span>收集</span>${sporeIcon}<strong>${selectedSave.bestCollected}</strong><span>/ ${totalSpores(selected)}</span></div><div class="map-chapter-progress" aria-label="本章已通关 ${completed} / ${levels.length}">${levels.map((l,i)=>`<i class="${state.save.levels[l.id].completed?'done':''} ${i===currentIndex?'selected':''}"></i>`).join('')}</div><button class="map-enter-button" data-level="${selected.id}" ${selectedSave.unlocked?'':'disabled'}>${selectedSave.completed?'重访关卡':selectedSave.unlocked?'进入关卡':'等待前一关苏醒'} <span>✿</span></button><small class="chapter-collection">本章微光 ${chapterCollected} / ${chapterTotal} · 已唤醒 ${completed} / 4</small></aside>
    <nav class="illustrated-chapter-cards" aria-label="切换章节">${nextChapters.map(c=>{
      const list=LEVELS.filter(l=>l.chapter===c.id);const unlocked=list.some(l=>state.save.levels[l.id].unlocked);const count=list.filter(l=>state.save.levels[l.id].completed).length;
      return `<button class="illustrated-chapter-card ${!unlocked?'chapter-sleeping':''}" data-map-chapter="${c.id}" aria-label="查看${c.title}，${unlocked?'已开启':'尚未解锁'}"><div style="background-image:url('./images/reference-scenes/chapter-${c.id}.jpg')">${!unlocked?lockIcon:'<span>✧</span>'}</div><h3>${c.title}</h3><small>${unlocked?`已唤醒 ${count} / 4`:'静待微光唤醒'}</small></button>`;
    }).join('')}</nav>
    <button class="map-world-button" data-action="世界总览">${materialIcon('map')}<small>世界总览</small></button><div class="map-floating-light" aria-hidden="true">${particles()}</div>
    ${state.mapOverview?`<section class="world-overview-layer" role="dialog" aria-modal="true" aria-labelledby="worldTitle"><div class="world-overview-paper"><button class="world-close" data-action="关闭世界总览" aria-label="关闭世界总览">×</button><span class="map-panel-eyebrow">THE WORLD OF SPORELIGHT</span><h2 id="worldTitle">微光走过的地方</h2><div class="world-overview-chapters">${CHAPTERS.map((c,i)=>`<button data-map-chapter="${c.id}"><img src="./images/reference-scenes/chapter-${c.id}.jpg" alt="${c.title}的遗迹景色"/><small>第 ${i+1} 章</small><h3>${c.title}</h3><p>${c.description}</p><span>${LEVELS.filter(l=>l.chapter===c.id&&state.save.levels[l.id].completed).length} / 4 已唤醒</span></button>`).join('')}</div></div></section>`:''}
  </div>`;
}
