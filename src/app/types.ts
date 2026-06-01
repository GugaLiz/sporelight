export type Scene = 'boot' | 'naming' | 'mainMenu' | 'levelSelect' | 'game' | 'result' | 'gallery';
export type Quality = 'soft' | 'standard' | 'hd';
export type Language = 'zh-CN' | 'zh-TW' | 'en';
export type LevelId = 'valley' | 'pond' | 'cave';
export type ConfirmMode = 'resetName' | 'resetSettings' | null;

export interface LevelSave {
  unlocked: boolean;
  completed: boolean;
  bestStars: number;
}

export interface SaveData {
  playerName: string;
  hasNamed: boolean;
  lastLevel: LevelId;
  levels: Record<LevelId, LevelSave>;
  gallery: Record<string, boolean>;
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
}

export interface AppState {
  save: SaveData;
  scene: Scene;
  settingsOpen: boolean;
  confirmMode: ConfirmMode;
  bootReady: boolean;
}
