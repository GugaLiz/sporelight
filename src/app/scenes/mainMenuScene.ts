import type { AppState } from '../types';
import { LEVELS } from '../game/levels';
import { escapeHtml, materialIcon } from '../ui';
import {loadGardenProgress} from '../garden2/save';
export function renderMainMenuScene(state: AppState) {
  const progress=loadGardenProgress();const completed=Object.values(progress.records).filter(r=>r.completed).length;
  const canResume=Object.keys(progress.runs).length>0||state.save.run||LEVELS.some(l=>state.save.levels[l.id].completed);
  return `<div class="screen journey-menu" style="background-image:url('./images/main/bg.png')">
    <div class="journey-scenery"><div class="journey-landscape journey-vignette" role="img" aria-label="露薇和小苔灵沿着石台追随微光，停下俯身看看它，再慢慢走回来。"><img class="journey-vignette-fallback" src="./images/menu-walk-redrawn/idle-front.png" alt=""/><canvas id="menuVignette" aria-hidden="true"></canvas></div></div>
    <div class="menu-shade"></div>
    <div class="journey-interface">
    <header class="journey-brand"><img class="material-brand-logo" src="./images/material-ready/menu-logo.png" alt=""/><span class="eyebrow">A LITTLE LIGHT. A LITTLE LIFE.</span><h1>微光苔原</h1><span class="brand-en">S P O R E L I G H T</span><p>把一粒微光，种成回家的路。</p></header>
    <div class="journey-invitation"><div class="tiny-leaf">✧</div><span class="eyebrow">一段温柔的冒险</span><h2>${completed ? '微光，还在等你。' : '你好，小小的旅人。'}</h2><p>${escapeHtml(state.save.playerName)}，这里没有需要赶上的时间。<br>走一走，让沉睡的生命重新发光。</p>
      <nav class="journey-menu-actions" aria-label="主菜单"><button class="j-button primary" data-action="开始游戏">开始旅程 2.0</button><button class="j-button" data-action="继续旅程" ${canResume ? '' : 'disabled'}>继续上次的微光</button><button class="cloud-menu-entry" data-action="云庭目录">云庭微光 ↗<small>独立样章 · 和小苔灵修复空中花园</small></button><div class="menu-secondary"><button data-action="图鉴">${materialIcon('gallery')}图鉴</button><button data-action="花园纪事">纪事</button><button data-action="设置">${materialIcon('settings')}设置</button></div></nav>
      <div class="journey-progress"><div><i style="width:${completed / 12 * 100}%"></i></div><span>已唤醒 ${completed} / 12 片微光</span></div>
    </div><footer class="journey-footer"><span>探索 · 播种 · 共生</span><span>没有失败，只有慢慢生长。</span></footer>
  </div></div>`;
}
