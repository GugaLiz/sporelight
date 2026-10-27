import { CHAPTERS, LEVELS, getLevel, type Chapter } from '../game/levels';
import type { AppState } from '../types';

/** Map markers follow the walkable terraces in the supplied chapter illustration. */
export const MAP_TERRACES = [
  { x: 112, y: 441 }, { x: 260, y: 390 },
  { x: 561, y: 485 }, { x: 799, y: 201 },
] as const;

export function mapPresentation(state: AppState) {
  const chapterId = state.mapChapter ?? getLevel(state.save.lastLevel).chapter;
  const chapter = CHAPTERS.find(c => c.id === chapterId) ?? CHAPTERS[0];
  const levels = LEVELS.filter(l => l.chapter === chapter.id);
  const selected = levels.find(l => l.id === state.mapLevel) ?? levels.find(l => l.id === state.save.lastLevel) ?? levels.find(l => state.save.levels[l.id].unlocked && !state.save.levels[l.id].completed) ?? levels[0];
  return { chapter, levels, selected };
}

export function plantImage(chapter: Chapter, completed: boolean, unlocked: boolean) {
  const filename = completed ? chapter === 'valley' ? 'plant-bloom' : `plant-${chapter}-bloom` : unlocked ? 'plant-bud' : 'plant-dormant';
  return `/images/reference-scenes/${filename}.png`;
}

export const lockIcon = `<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><rect x="6" y="10" width="12" height="11" rx="3" fill="currentColor"/><path d="M8 10V7a4 4 0 0 1 8 0v3" stroke="currentColor" stroke-width="2.5"/><circle cx="12" cy="15" r="1.5" fill="#817461"/></svg>`;
export const sporeIcon = `<svg class="illustrated-spore-icon" viewBox="0 0 40 40" aria-hidden="true"><circle cx="20" cy="20" r="12" fill="#ffefa8" fill-opacity=".35" stroke="#e7c270" stroke-width="1.3"/><circle cx="20" cy="20" r="7" fill="#fff5b4" stroke="#d9af50" stroke-width="1.5"/><path d="M20 1v5m0 28v5M1 20h5m28 0h5M6.5 6.5l3.5 3.5m20 20 3.5 3.5M6.5 33.5l3.5-3.5m20-20 3.5-3.5" stroke="#dfb765" stroke-width="1.5" stroke-linecap="round"/><circle cx="13" cy="12" r="2.2" fill="#fff9cd"/><circle cx="28" cy="25" r="2.4" fill="#fff9cd"/></svg>`;
