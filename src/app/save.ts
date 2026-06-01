import { DEFAULT_NAME, SAVE_KEY } from './constants';
import type { SaveData } from './types';

export function createDefaultSave(): SaveData {
  return {
    playerName: DEFAULT_NAME,
    hasNamed: false,
    lastLevel: 'valley',
    levels: {
      valley: { unlocked: true, completed: false, bestStars: 0 },
      pond: { unlocked: false, completed: false, bestStars: 0 },
      cave: { unlocked: false, completed: false, bestStars: 0 }
    },
    gallery: {
      flowerbud: false,
      moss: false,
      vine: false,
      bug: false,
      lilypad: false,
      mushroom: false,
      arch: false,
      starflower: false
    },
    settings: {
      bgm: 0.7,
      sfx: 0.6,
      ambient: 0.5,
      quality: 'standard',
      dynamicLight: true,
      particles: true,
      lowMotion: false,
      vibration: true,
      fullscreen: false,
      language: 'zh-CN'
    }
  };
}

function mergeSave(base: SaveData, partial: Partial<SaveData>): SaveData {
  return {
    ...base,
    ...partial,
    levels: { ...base.levels, ...partial.levels },
    gallery: { ...base.gallery, ...partial.gallery },
    settings: { ...base.settings, ...partial.settings }
  };
}

export function loadSave(): SaveData {
  try {
    const raw = localStorage.getItem(SAVE_KEY);

    if (!raw) {
      return createDefaultSave();
    }

    const parsed = JSON.parse(raw) as Partial<SaveData>;
    return mergeSave(createDefaultSave(), parsed);
  } catch {
    return createDefaultSave();
  }
}

export function persistSave(save: SaveData) {
  localStorage.setItem(SAVE_KEY, JSON.stringify(save));
}
