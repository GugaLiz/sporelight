import type { AppState } from '../types';
import { CHAPTERS, LEVELS, totalSpores } from '../game/levels';
export function renderLevelSelectScene(state: AppState) {
  const completed = LEVELS.filter(l => state.save.levels[l.id].completed).length;
  return `<div class="screen journey-map"><header class="journey-page-header"><button class="j-back" data-action="返回主菜单" aria-label="返回主菜单">←</button><div><span class="eyebrow">THE LITTLE JOURNEY</span><h1>循着微光，慢慢走。</h1></div><span class="header-progress">${completed} / 12 <small>已唤醒</small></span></header>
    <div class="chapter-grid">${CHAPTERS.map((chapter, index) => `<section class="chapter-card ${chapter.id}"><div class="chapter-cover" style="background-image:url('/images/production/bg-${chapter.id}.jpg')"><span class="chapter-number">0${index + 1}</span><div><span class="eyebrow">${chapter.english}</span><h2>${chapter.title}</h2></div></div><p>${chapter.description}</p><div class="chapter-levels">${LEVELS.filter(l => l.chapter === chapter.id).map(level => {
      const data = state.save.levels[level.id];
      return `<button class="chapter-level ${data.completed ? 'completed' : ''}" data-level="${level.id}" ${data.unlocked ? '' : 'disabled'} aria-label="${level.id} ${level.title}${data.unlocked ? '' : '，通关上一关后解锁'}"><span class="level-index">${data.completed ? '✓' : data.unlocked ? level.id : '·'}</span><span><strong>${level.title}</strong><small>${data.completed ? `孢子 ${data.bestCollected}/${totalSpores(level)}` : data.unlocked ? '等待你的脚步' : '通关上一关后解锁'}</small></span><span class="level-stars">${data.completed ? '✦'.repeat(data.bestStars) : data.unlocked ? '↗' : '锁定'}</span></button>`;
    }).join('')}</div></section>`).join('')}</div><footer class="map-footer">不必收集每一粒孢子，也能走到远方。<span>最后的仪式，需要八粒完整的微光。</span></footer></div>`;
}
