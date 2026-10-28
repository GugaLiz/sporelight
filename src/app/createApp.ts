import { DEFAULT_NAME, RANDOM_NAMES } from './constants';
import { renderSettingsModal } from './components/settingsModal';
import { CanvasGame } from './game/CanvasGame';
import { Soundscape } from './game/audio';
import { CHARACTER_FILES } from './game/characterMotion';
import { CHAPTERS, LEVELS, getLevel } from './game/levels';
import { createDefaultSave, loadSave, persistSave } from './save';
import { renderBootScene } from './scenes/bootScene';
import { renderGalleryScene } from './scenes/galleryScene';
import { GALLERY_CATEGORIES, gallerySelection, type GalleryCategory, type GalleryMode } from './scenes/galleryData';
import { renderGameScene } from './scenes/gameScene';
import { renderLevelSelectScene } from './scenes/levelSelectScene';
import { renderMainMenuScene } from './scenes/mainMenuScene';
import { renderNamingScene } from './scenes/namingScene';
import { renderResultScene } from './scenes/resultScene';
import type { AppState, GameSnapshot, Quality, Scene } from './types';
import { bindActions } from './ui';
import { CloudGame } from './cloud/CloudGame';
import { CloudRenderer } from './cloud/renderer';
import { CloudModel, loadCloudSave, storeCloudSave } from './cloud/model';
import { CLOUD_LEVELS, type CloudLevelId } from './cloud/data';
import { renderCloudGame, renderCloudLobby } from './cloud/scenes';

export function createApp(root: HTMLDivElement) { const app = new SporelightApp(root); app.mount(); return app; }
class SporelightApp {
  private state: AppState = { save: loadSave(), scene: 'boot', settingsOpen: false, confirmMode: null, bootReady: false };
  private game: CanvasGame | null = null;
  private cloud: CloudGame | null = null;
  private cloudSave = loadCloudSave();
  private cloudId: CloudLevelId = this.cloudSave.lastLevel;
  private cloudReview = false;
  private cloudPreviewObservers: ResizeObserver[] = [];
  private audio = new Soundscape(this.state.save.settings);
  private storageWarned = false;
  private beforeModalFocus: HTMLElement | null = null;
  private timer = 0;
  constructor(private root: HTMLDivElement) {}
  mount() {
    this.render();
    window.addEventListener('resize', this.resize);
    window.addEventListener('keydown', this.onGlobalKey);
    document.addEventListener('visibilitychange', this.onVisibility);
    document.addEventListener('fullscreenchange', this.onFullscreen);
    this.root.addEventListener('pointerdown', this.startAudio);
    this.root.addEventListener('keydown', this.startAudio);
    const resources = [...['idle1.png', 'soil.png', 'bloom.png', 'bg-valley.jpg'].map(file => `./images/production/${file}`), ...CHARACTER_FILES.map(file => `./images/material-ready/${file}.png`)];
    const loads = resources.map(file => new Promise<void>(resolve => {
      const image = new Image(); image.onload = () => resolve(); image.onerror = () => resolve(); image.src = file;
    }));
    this.timer = window.setTimeout(() => this.finishBoot(), 5000);
    void Promise.all(loads).then(() => { if (this.state.scene === 'boot') { clearTimeout(this.timer); this.timer = window.setTimeout(() => this.finishBoot(), 600); } });
  }
  private finishBoot() { if (this.state.scene !== 'boot') return; this.state.bootReady = true; this.setScene(this.state.save.hasNamed ? 'mainMenu' : 'naming'); }
  private render() {
    this.game?.destroy(); this.game = null;
    this.cloud?.destroy(); this.cloud = null;
    this.cloudPreviewObservers.forEach(observer => observer.disconnect()); this.cloudPreviewObservers = [];
    const views = { boot: renderBootScene, naming: renderNamingScene, mainMenu: renderMainMenuScene, levelSelect: renderLevelSelectScene, game: renderGameScene, result: renderResultScene, gallery: renderGalleryScene, cloudLobby: renderCloudLobby, cloudGame: renderCloudGame };
    this.root.innerHTML = `<main class="shell ${this.state.save.settings.lowMotion ? 'is-low-motion' : ''}"><section class="stage stage--${this.state.scene}" style="--scene-scale:${this.scale()}">${views[this.state.scene](this.state)}</section><div id="modalRoot"></div><aside class="orientation-note">横过屏幕，让这片微光更宽一点。<span>也可以保持竖屏继续游玩</span></aside></main>`;
    this.bindScene();
  }
  private bindScene() {
    bindActions({
      randomName: () => this.setName(RANDOM_NAMES[Math.floor(Math.random() * RANDOM_NAMES.length)]),
      resetNameField: () => this.setName(DEFAULT_NAME), startJourney: () => this.submitName(),
      开始游戏: () => this.setScene('levelSelect'), 继续旅程: () => this.enterLevel(this.state.save.run?.levelId ?? this.state.save.lastLevel, true),
      图鉴: () => this.setScene('gallery'), 设置: () => this.openSettings(),
      云庭目录: () => this.setScene('cloudLobby'),
      返回主菜单: () => this.setScene('mainMenu'), 返回关卡选择: () => this.setScene('levelSelect'),
      播种: () => this.game?.sow(), 撤销: () => this.game?.undo(), 提示: () => this.game?.hint(),
      切换移动: () => this.game?.toggleMovementMode(),
      跳跃: () => this.game?.jump(),
      重来: () => this.enterLevel(this.state.save.lastLevel, false), 重玩: () => this.enterLevel(this.state.save.lastLevel, false),
      下一关: () => { const i = LEVELS.findIndex(l => l.id === this.state.save.lastLevel); if (LEVELS[i + 1]) this.enterLevel(LEVELS[i + 1].id, false); else this.setScene('gallery'); },
      世界总览: () => { this.state.mapOverview = true; this.render(); },
      关闭世界总览: () => { this.state.mapOverview = false; this.render(); document.querySelector<HTMLButtonElement>('[data-action="世界总览"]')?.focus(); },
    });
    if (this.state.scene === 'cloudLobby') {
      this.root.querySelectorAll<HTMLButtonElement>('[data-cloud-enter]').forEach(b => b.addEventListener('click', () => this.enterCloud(b.dataset.cloudEnter as CloudLevelId)));
      this.root.querySelectorAll<HTMLButtonElement>('[data-cloud-review]').forEach(b => b.addEventListener('click', () => this.enterCloud(b.dataset.cloudReview as CloudLevelId, true)));
      this.root.querySelectorAll<HTMLCanvasElement>('[data-cloud-preview]').forEach(canvas => {
        const id = canvas.dataset.cloudPreview as CloudLevelId;
        const model = new CloudModel(id, this.cloudSave.memories[id] ?? this.cloudSave.runs[id]);
        model.state.repaired = this.cloudSave.completed.includes(id);
        const renderer = new CloudRenderer(canvas, model, this.state.save.settings); renderer.draw(0);
        const observer = new ResizeObserver(() => { renderer.resize(); renderer.draw(0); }); observer.observe(canvas); this.cloudPreviewObservers.push(observer);
      });
    }
    if (this.state.scene === 'cloudGame') {
      this.cloud = new CloudGame(this.root.querySelector<HTMLCanvasElement>('#cloudCanvas')!, this.cloudId, this.cloudSave, this.state.save.settings,
        () => { if (!storeCloudSave(this.cloudSave)) this.root.querySelector<HTMLElement>('#cloudStorageWarning')!.hidden = false; },
        id => this.enterCloud(id), kind => this.audio.play(kind), this.cloudReview);
    }
    document.querySelectorAll<HTMLButtonElement>('[data-map-level]').forEach(button => button.addEventListener('click', () => {
      this.state.mapLevel = button.dataset.mapLevel;
      this.render();
      document.querySelector<HTMLButtonElement>(`[data-map-level="${this.state.mapLevel}"]`)?.focus();
    }));
    document.querySelectorAll<HTMLButtonElement>('[data-map-chapter]').forEach(button => button.addEventListener('click', () => {
      const chapter = CHAPTERS.find(c => c.id === button.dataset.mapChapter);
      if (!chapter) return;
      this.state.mapChapter = chapter.id;
      const levels = LEVELS.filter(l => l.chapter === chapter.id);
      this.state.mapLevel = (levels.find(l => this.state.save.levels[l.id].unlocked && !this.state.save.levels[l.id].completed) ?? levels[0]).id;
      this.state.mapOverview = false;
      this.render();
    }));
    if (this.state.mapOverview && this.state.scene === 'levelSelect') {
      document.querySelectorAll<HTMLElement>('.illustrated-map > :not(.world-overview-layer)').forEach(el => { el.inert = true; });
      document.querySelector<HTMLButtonElement>('.world-close')?.focus();
    }
    document.querySelectorAll<HTMLButtonElement>('[data-level]').forEach(button => button.addEventListener('click', () => this.enterLevel(button.dataset.level!, true)));
    document.getElementById('playerNameInput')?.addEventListener('keydown', event => { if (event.key === 'Enter') this.submitName(); });
    if (this.state.scene === 'game') {
      this.game = new CanvasGame(document.querySelector<HTMLCanvasElement>('#gameCanvas')!, this.state.save.lastLevel, this.state.save.run, this.state.save.settings,
        run => { this.state.save.run = run.completed ? null : run; this.persist(); }, snapshot => this.onComplete(snapshot), kind => this.audio.play(kind));
      this.state.save.run = this.game.model.snapshot(); this.persist();
    }
    if (this.state.scene === 'gallery') {
      const focus = (selector:string) => document.querySelector<HTMLButtonElement>(selector)?.focus({preventScroll:true});
      const category = (value:GalleryCategory) => {
        this.state.galleryCategory = value;
        this.state.gallerySelected = gallerySelection(this.state).selected?.id;
        this.render();focus(`[data-gallery-cat="${value}"]`);
      };
      document.querySelectorAll<HTMLButtonElement>('[data-gallery-cat]').forEach(tab => {
        tab.addEventListener('click', () => category(tab.dataset.galleryCat as GalleryCategory));
        tab.addEventListener('keydown', event => {
          if(!['ArrowLeft','ArrowRight','Home','End'].includes(event.key))return;
          event.preventDefault();const index=GALLERY_CATEGORIES.indexOf(tab.dataset.galleryCat as GalleryCategory);
          const next=event.key==='Home'?0:event.key==='End'?GALLERY_CATEGORIES.length-1:(index+(event.key==='ArrowRight'?1:-1)+GALLERY_CATEGORIES.length)%GALLERY_CATEGORIES.length;
          category(GALLERY_CATEGORIES[next]);
        });
      });
      document.querySelectorAll<HTMLButtonElement>('[data-gallery-id]').forEach(card => card.addEventListener('click', () => {
        const scrollTop=document.querySelector<HTMLElement>('.illustrated-gallery')?.scrollTop??0;
        this.state.gallerySelected = card.dataset.galleryId;
        this.render();document.querySelector<HTMLElement>('.illustrated-gallery')!.scrollTop=scrollTop;focus(`[data-gallery-id="${this.state.gallerySelected}"]`);
        if(window.innerWidth<window.innerHeight)document.querySelector('.journal-side-tabs')?.scrollIntoView({behavior:this.state.save.settings.lowMotion?'auto':'smooth',block:'start'});
      }));
      const mode=(value:GalleryMode)=>{const scrollTop=document.querySelector<HTMLElement>('.illustrated-gallery')?.scrollTop??0;this.state.galleryMode=value;this.render();document.querySelector<HTMLElement>('.illustrated-gallery')!.scrollTop=scrollTop;focus(`[data-gallery-mode="${value}"]`);};
      document.querySelectorAll<HTMLButtonElement>('[data-gallery-mode]').forEach(tab=>{
        tab.addEventListener('click',()=>mode(tab.dataset.galleryMode as GalleryMode));
        tab.addEventListener('keydown',event=>{if(!['ArrowUp','ArrowDown','ArrowLeft','ArrowRight'].includes(event.key))return;event.preventDefault();mode(tab.dataset.galleryMode==='entry'?'story':'entry');});
      });
      document.querySelector<HTMLButtonElement>('[data-gallery-list]')?.addEventListener('click',()=>document.getElementById('galleryGrid')?.scrollIntoView({behavior:this.state.save.settings.lowMotion?'auto':'smooth',block:'start'}));
    }
  }

  private enterCloud(id: CloudLevelId, review = false) {
    const index = CLOUD_LEVELS.findIndex(l => l.id === id);
    if (index < 0 || index > 0 && !this.cloudSave.completed.includes(CLOUD_LEVELS[index - 1].id)) return;
    if (review && !this.cloudSave.completed.includes(id)) return;
    this.cloudId = id; this.cloudReview = review;
    if (!review) {
      if (this.cloudSave.runs[id]?.repaired) delete this.cloudSave.runs[id];
      this.cloudSave.lastLevel = id; storeCloudSave(this.cloudSave);
    }
    this.setScene('cloudGame');
  }
  private enterLevel(id: string, resume: boolean) {
    if (!this.state.save.levels[id]?.unlocked) { this.toast('先唤醒前一片苔原，再来这里吧。'); return; }
    const run = resume && this.state.save.run?.levelId === id ? this.state.save.run : null;
    this.state.save.run = run; this.state.save.lastLevel = id; this.persist(); this.setScene('game');
  }
  private setScene(next: Scene) {
    this.state.mapOverview = false;
    if (next === 'levelSelect') {
      this.state.mapLevel = this.state.save.lastLevel;
      this.state.mapChapter = getLevel(this.state.save.lastLevel).chapter;
    }
    clearTimeout(this.timer); this.state.settingsOpen = false; this.state.confirmMode = null; this.state.scene = next; this.render();
  }
  private onComplete(result: GameSnapshot) {
    this.state.result = result;
    const level = getLevel(result.levelId); const score = this.state.save.levels[level.id];
    score.completed = true; score.bestStars = Math.max(score.bestStars, result.stars); score.bestCollected = Math.max(score.bestCollected, result.collected);
    const next = LEVELS[LEVELS.indexOf(level) + 1]; if (next) this.state.save.levels[next.id].unlocked = true;
    level.rewards.forEach(id => { this.state.save.gallery[id] = true; });
    this.state.save.run = null; this.persist();
    this.timer = window.setTimeout(() => { if (this.state.scene === 'game') this.setScene('result'); }, 650);
  }
  private setName(name: string) { const input = document.querySelector<HTMLInputElement>('#playerNameInput'); if (input) input.value = name; }
  private submitName() {
    const name = document.querySelector<HTMLInputElement>('#playerNameInput')?.value.trim() ?? '';
    if (!/^[\u4e00-\u9fa5A-Za-z0-9 ]{1,12}$/.test(name)) { document.getElementById('nameError')!.textContent = '请输入 1–12 个中文、英文或数字。'; return; }
    this.state.save.playerName = name; this.state.save.hasNamed = true; this.persist(); this.setScene('mainMenu');
  }
  private persist() { if (!persistSave(this.state.save) && !this.storageWarned) { this.storageWarned = true; this.toast('浏览器暂时无法保存，本次仍可游玩；关闭页面后可能丢失进度。'); } }
  private openSettings() {
    if (this.game?.model.state.completed) return;
    this.beforeModalFocus = document.activeElement as HTMLElement;
    this.state.settingsOpen = true; this.game?.pause(true); this.cloud?.pause(true); this.renderSettings();
    this.root.querySelector<HTMLElement>('.stage')!.inert = true;
  }
  private closeSettings() {
    this.state.settingsOpen = false; this.state.confirmMode = null;
    document.getElementById('modalRoot')!.innerHTML = ''; this.root.querySelector<HTMLElement>('.stage')!.inert = false;
    this.game?.pause(document.hidden); this.cloud?.pause(document.hidden); this.beforeModalFocus?.focus();
  }
  private renderSettings() {
    const modal = document.getElementById('modalRoot')!; modal.innerHTML = renderSettingsModal(this.state);
    bindActions({ 关闭设置: () => this.closeSettings(), 重置名称: () => { this.closeSettings(); this.setScene('naming'); },
      恢复默认设置: () => { this.state.confirmMode = 'resetSettings'; this.renderSettings(); },
      取消确认: () => { this.state.confirmMode = null; this.renderSettings(); },
      确认操作: () => { this.state.save.settings = createDefaultSave().settings; this.state.confirmMode = null; this.applySettings(); this.renderSettings(); },
      全屏: () => { void this.fullscreen(); },
    });
    modal.querySelectorAll<HTMLInputElement>('[data-setting-slider]').forEach(input => input.addEventListener('input', () => {
      const key = input.dataset.settingSlider as 'bgm' | 'sfx' | 'ambient'; this.state.save.settings[key] = Number(input.value) / 100;
      input.closest('label')?.querySelector('output')?.replaceChildren(`${input.value}%`); this.applySettings();
    }));
    modal.querySelectorAll<HTMLButtonElement>('[data-setting-toggle]').forEach(button => button.addEventListener('click', () => {
      const key = button.dataset.settingToggle as 'dynamicLight' | 'particles' | 'lowMotion' | 'vibration'; this.state.save.settings[key] = !this.state.save.settings[key];
      this.applySettings(); button.setAttribute('aria-pressed', String(this.state.save.settings[key])); button.querySelector('i')!.textContent = this.state.save.settings[key] ? '开' : '关';
    }));
    modal.querySelectorAll<HTMLButtonElement>('[data-quality]').forEach(button => button.addEventListener('click', () => {
      this.state.save.settings.quality = button.dataset.quality as Quality; this.applySettings();
      modal.querySelectorAll('[data-quality]').forEach(el => { el.classList.toggle('selected', el === button); el.setAttribute('aria-pressed', String(el === button)); });
    }));
    const confirm = modal.querySelector('.j-confirm');
    if (confirm) modal.querySelectorAll<HTMLElement>('.journey-settings > :not(.j-confirm)').forEach(el => el.inert = true);
    (confirm ?? modal).querySelector<HTMLButtonElement>('button')?.focus();
  }
  private applySettings() {
    this.persist(); this.audio.configure(this.state.save.settings); this.game?.configure(this.state.save.settings); this.cloud?.configure(this.state.save.settings);
    this.root.querySelector('.shell')?.classList.toggle('is-low-motion', this.state.save.settings.lowMotion);
  }
  private async fullscreen() {
    try { if (document.fullscreenElement) await document.exitFullscreen(); else await document.documentElement.requestFullscreen(); }
    catch { this.toast('当前浏览器不支持全屏，请使用浏览器的全屏功能。'); }
  }
  private onFullscreen = () => { if (this.state.settingsOpen) this.renderSettings(); };
  private onVisibility = () => { this.audio.pause(document.hidden); this.game?.pause(document.hidden || this.state.settingsOpen); this.cloud?.pause(document.hidden || this.state.settingsOpen); };
  private startAudio = () => this.audio.start();
  private onGlobalKey = (event: KeyboardEvent) => {
    if (this.state.mapOverview) {
      if (event.key === 'Escape') { event.preventDefault(); this.state.mapOverview = false; this.render(); document.querySelector<HTMLButtonElement>('[data-action="世界总览"]')?.focus(); }
      if (event.key === 'Tab') {
        const items = Array.from(this.root.querySelectorAll<HTMLButtonElement>('.world-overview-layer button'));
        const first = items[0]; const last = items[items.length - 1];
        if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
        else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
      }
      return;
    }
    if (event.key === 'Escape') { event.preventDefault(); if (this.state.settingsOpen) { if (this.state.confirmMode) { this.state.confirmMode = null; this.renderSettings(); } else this.closeSettings(); } else if (this.state.scene !== 'boot') this.openSettings(); }
    if (event.key === 'Tab' && this.state.settingsOpen) {
      const dialog = this.root.querySelector('.j-confirm') ?? this.root.querySelector('.journey-settings')!;
      const items = Array.from(dialog.querySelectorAll<HTMLElement>('button:not(:disabled),input,select')).filter(el => !el.closest('[inert]'));
      const first = items[0]; const last = items[items.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
    }
  };
  private resize = () => { this.root.querySelector<HTMLElement>('.stage')?.style.setProperty('--scene-scale', String(this.scale())); };
  private scale() { return Math.min(window.innerWidth / 1280, window.innerHeight / 720); }
  private toast(message: string) {
    this.root.querySelector('.toast')?.remove(); const toast = document.createElement('div'); toast.className = 'toast'; toast.role = 'status'; toast.textContent = message; this.root.appendChild(toast); window.setTimeout(() => toast.remove(), 4500);
  }
  destroy() {
    clearTimeout(this.timer); this.game?.destroy(); this.cloud?.destroy(); this.audio.destroy();
    this.cloudPreviewObservers.forEach(observer => observer.disconnect());
    window.removeEventListener('resize', this.resize); window.removeEventListener('keydown', this.onGlobalKey);
    document.removeEventListener('visibilitychange', this.onVisibility); document.removeEventListener('fullscreenchange', this.onFullscreen);
    this.root.removeEventListener('pointerdown', this.startAudio); this.root.removeEventListener('keydown', this.startAudio);
  }
}
