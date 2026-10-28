export type Scene = 'boot' | 'naming' | 'mainMenu' | 'levelSelect' | 'game' | 'result' | 'gallery' | 'cloudLobby' | 'cloudGame';
export type Quality = 'soft' | 'standard' | 'hd';
export type Language = 'zh-CN' | 'zh-TW' | 'en';
export type LevelId = string;
export type ConfirmMode = 'resetName' | 'resetSettings' | null;

export interface LevelSave {
  unlocked: boolean;
  completed: boolean;
  bestStars: number;
  bestCollected: number;
}

export interface SaveData {
  version: 2;
  playerName: string;
  hasNamed: boolean;
  lastLevel: LevelId;
  levels: Record<LevelId, LevelSave>;
  gallery: Record<string, boolean>;
  run: import('./game/model').RunState | null;
  settings: {
    bgm: number;
    sfx: number;
    ambient: number;
    quality: Quality;
    dynamicLight: boolean;
    particles: boolean;
    lowMotion: boolean;
    vibration: boolean;
    fullscreen: boolean;
    language: Language;
  };
}

export interface GameSnapshot {
  completed: boolean;
  seeds: boolean[];
  levelId: string;
  collected: number;
  total: number;
  stars: number;
  awakened: number;
}

export interface AppState {
  save: SaveData;
  scene: Scene;
  settingsOpen: boolean;
  confirmMode: ConfirmMode;
  bootReady: boolean;
  result?: GameSnapshot;
  mapChapter?: import('./game/levels').Chapter;
  mapLevel?: string;
  mapOverview?: boolean;
  galleryCategory?: import('./scenes/galleryData').GalleryCategory;
  gallerySelected?: string;
  galleryMode?: import('./scenes/galleryData').GalleryMode;
}
