import type { AppState } from '../types';
import { LEVELS } from '../game/levels';
import { escapeHtml } from '../ui';
export function renderMainMenuScene(state: AppState) {
  const completed = LEVELS.filter(l => state.save.levels[l.id].completed).length;
  return `<div class="screen journey-menu" style="background-image:url('/images/main/bg.png')">
    <div class="menu-shade"></div>
    <header class="journey-brand"><span class="eyebrow">A LITTLE LIGHT. A LITTLE LIFE.</span><h1>微光苔原</h1><span class="brand-en">S P O R E L I G H T</span><p>把一粒微光，种成回家的路。</p></header>
    <img class="journey-companion" src="/images/production/hero.png" alt="戴着红色蘑菇帽的露薇" />
    <div class="journey-invitation"><div class="tiny-leaf">✧</div><span class="eyebrow">一段温柔的冒险</span><h2>${completed ? '微光，还在等你。' : '你好，小小的旅人。'}</h2><p>${escapeHtml(state.save.playerName)}，这里没有需要赶上的时间。<br>走一走，让沉睡的生命重新发光。</p>
      <nav class="journey-menu-actions" aria-label="主菜单"><button class="j-button primary" data-action="开始游戏">开始旅程 <span>↗</span></button><button class="j-button" data-action="继续旅程" ${state.save.run || completed ? '' : 'disabled'}>继续上次的微光 <span>→</span></button><div class="menu-secondary"><button data-action="图鉴">❧ 自然图鉴</button><button data-action="设置">⚙ 设置</button></div></nav>
      <div class="journey-progress"><div><i style="width:${completed / 12 * 100}%"></i></div><span>已唤醒 ${completed} / 12 片微光</span></div>
    </div><footer class="journey-footer"><span>探索 · 播种 · 共生</span><span>没有失败，只有慢慢生长。</span></footer>
  </div>`;
}
