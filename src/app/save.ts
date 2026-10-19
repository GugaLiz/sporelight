import { DEFAULT_NAME, SAVE_KEY } from './constants';
import { LEVELS, totalSpores } from './game/levels';
import { GameModel } from './game/model';
import type { SaveData } from './types';
export function createDefaultSave(): SaveData {
  return {
    version: 2, playerName: DEFAULT_NAME, hasNamed: false, lastLevel: '1-1', run: null,
    levels: Object.fromEntries(LEVELS.map((l, i) => [l.id, { unlocked: i === 0, completed: false, bestStars: 0, bestCollected: 0 }])),
    gallery: Object.fromEntries(['flowerbud', 'moss', 'vine', 'bug', 'lilypad', 'mushroom', 'arch', 'starflower'].map(id => [id, false])),
    settings: { bgm: .35, sfx: .6, ambient: .25, quality: 'standard', dynamicLight: true, particles: true, lowMotion: false, vibration: false, fullscreen: false, language: 'zh-CN' },
  };
}
const record = (v: unknown): Record<string, any> => v && typeof v === 'object' && !Array.isArray(v) ? v : {};
const integer = (v: unknown, max: number) => typeof v === 'number' && Number.isFinite(v) ? Math.min(max, Math.max(0, Math.floor(v))) : 0;
export function normalizeSave(raw: unknown): SaveData {
  const input = record(raw); const save = createDefaultSave();
  if (typeof input.playerName === 'string' && /^[\u4e00-\u9fa5A-Za-z0-9 ]{1,12}$/.test(input.playerName.trim())) save.playerName = input.playerName.trim();
  save.hasNamed = input.hasNamed === true;
  const levels = record(input.levels);
  LEVELS.forEach((level, i) => {
    const old = record(levels[level.id] ?? (i === 0 ? levels.valley : undefined));
    save.levels[level.id] = { unlocked: i === 0 || save.levels[LEVELS[i - 1].id].completed,
      completed: old.completed === true && (i === 0 || save.levels[LEVELS[i - 1].id].completed),
      bestStars: integer(old.bestStars, 3), bestCollected: integer(old.bestCollected, totalSpores(level)) };
  });
  if (typeof input.lastLevel === 'string' && save.levels[input.lastLevel]?.unlocked) save.lastLevel = input.lastLevel;
  const gallery = record(input.gallery);
  for (const id of Object.keys(save.gallery)) save.gallery[id] = gallery[id] === true;
  for (const level of LEVELS) if (save.levels[level.id].completed) for (const id of level.rewards) save.gallery[id] = true;
  const settings = record(input.settings);
  for (const key of ['bgm', 'sfx', 'ambient'] as const) if (typeof settings[key] === 'number' && Number.isFinite(settings[key])) save.settings[key] = Math.max(0, Math.min(1, settings[key]));
  for (const key of ['dynamicLight', 'particles', 'lowMotion', 'vibration'] as const) if (typeof settings[key] === 'boolean') save.settings[key] = settings[key];
  if (['soft', 'standard', 'hd'].includes(settings.quality)) save.settings.quality = settings.quality;
  const run = record(input.run); const level = LEVELS.find(l => l.id === run.levelId);
  if (level && save.levels[level.id].unlocked && !run.completed) save.run = new GameModel(level, run).snapshot();
  return save;
}
export function loadSave(): SaveData {
  try { const raw = localStorage.getItem(SAVE_KEY) ?? localStorage.getItem('sporelight.save.v1'); return raw ? normalizeSave(JSON.parse(raw)) : createDefaultSave(); }
  catch { return createDefaultSave(); }
}
export function persistSave(save: SaveData): boolean {
  try { localStorage.setItem(SAVE_KEY, JSON.stringify(save)); return true; } catch { return false; }
}
