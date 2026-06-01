import { BOOT_DURATION_MS, DEFAULT_NAME, RANDOM_NAMES, STARTUP_ASSET_ROOT, STARTUP_LOADING_FRAME_FILES } from './constants';
import { asset } from './assets';
import { renderSettingsModal } from './components/settingsModal';
import { CanvasGame } from './game/CanvasGame';
import { createDefaultSave, loadSave, persistSave } from './save';
import { renderBootScene } from './scenes/bootScene';
import { renderGalleryScene } from './scenes/galleryScene';
import { renderGameScene } from './scenes/gameScene';
import { renderLevelSelectScene } from './scenes/levelSelectScene';
import { renderMainMenuScene } from './scenes/mainMenuScene';
import { renderNamingScene } from './scenes/namingScene';
import { renderResultScene } from './scenes/resultScene';
import type { AppState, GameSnapshot, Language, Quality, SaveData, Scene } from './types';
import { bindActions } from './ui';

export function createApp(root: HTMLDivElement) {
  const app = new SporelightApp(root);
  app.mount();
  return app;
}

class SporelightApp {
  private state: AppState = {
    save: loadSave(),
    scene: 'boot',
    settingsOpen: false,
    confirmMode: null,
    bootReady: false
  };
  private game: CanvasGame | null = null;
  private bootTimer = 0;
  private bootFrameTimer = 0;

  constructor(private readonly root: HTMLDivElement) {
    window.addEventListener('resize', this.handleResize);
  }

  mount() {
    this.render();
  }

  private render() {
    this.destroyGame();

    this.root.innerHTML = `
      <main class="shell ${this.state.save.settings.lowMotion ? 'is-low-motion' : ''}">
        <section class="stage stage--${this.state.scene} stage--${this.viewportMode()}" style="--scene-scale: ${this.viewportScale()};">
          ${this.renderScene()}
        </section>
        ${this.state.settingsOpen ? renderSettingsModal(this.state) : ''}
      </main>
    `;

    this.bindScene();

    if (this.state.settingsOpen) {
      this.bindSettings();
    }

    if (this.state.scene === 'boot') {
      this.ensureBootSequence();
    }
  }

  private renderScene() {
    switch (this.state.scene) {
      case 'boot':
        return renderBootScene(this.state);
      case 'naming':
        return renderNamingScene(this.state);
      case 'mainMenu':
        return renderMainMenuScene(this.state);
      case 'levelSelect':
        return renderLevelSelectScene(this.state);
      case 'game':
        return renderGameScene();
      case 'result':
        return renderResultScene(this.state);
      case 'gallery':
        return renderGalleryScene(this.state);
    }
  }

  private bindScene() {
    bindActions({
      randomName: () => this.randomizeName(),
      resetNameField: () => this.setNameInput(DEFAULT_NAME),
      startJourney: () => this.submitName(),
      开始游戏: () => this.setScene('levelSelect'),
      继续旅程: () => this.setScene('levelSelect'),
      图鉴: () => this.setScene('gallery'),
      设置: () => this.openSettings(),
      返回主菜单: () => this.setScene('mainMenu'),
      返回关卡选择: () => this.setScene('levelSelect'),
      进入苔藓山谷: () => this.setScene('game'),
      锁定关卡: () => this.showToast('这片苔原还在沉睡。'),
      播种: () => this.game?.sow(),
      重玩: () => this.setScene('game')
    });

    if (this.state.scene === 'game') {
      const canvas = document.querySelector<HTMLCanvasElement>('#gameCanvas');
      const tip = document.querySelector<HTMLElement>('#gameTip');

      if (canvas) {
        this.game = new CanvasGame(canvas, tip, (snapshot) => this.onGameComplete(snapshot));
      }
    }
  }

  private bindSettings() {
    bindActions({
      关闭设置: () => this.closeSettings(),
      重置名称: () => {
        this.state.confirmMode = 'resetName';
        this.render();
      },
      恢复默认设置: () => {
        this.state.confirmMode = 'resetSettings';
        this.render();
      },
      取消确认: () => {
        this.state.confirmMode = null;
        this.render();
      },
      确认操作: () => this.confirmSettingsAction()
    });

    document.querySelectorAll<HTMLInputElement>('[data-setting-slider]').forEach((input) => {
      input.addEventListener('input', () => {
        const key = input.dataset.settingSlider as 'bgm' | 'sfx' | 'ambient';
        this.state.save.settings[key] = Number(input.value) / 100;
        input.closest('.settings-slider')?.querySelector('em')?.replaceChildren(`${input.value}%`);
        this.persist();
      });
    });

    document.querySelectorAll<HTMLButtonElement>('[data-setting-toggle]').forEach((toggle) => {
      toggle.addEventListener('click', () => {
        const key = toggle.dataset.settingToggle as keyof SaveData['settings'];
        const current = this.state.save.settings[key];

        if (typeof current === 'boolean') {
          this.state.save.settings[key] = !current as never;
          this.persist();
          this.render();
        }
      });
    });

    document.querySelectorAll<HTMLButtonElement>('[data-quality]').forEach((tab) => {
      tab.addEventListener('click', () => {
        this.state.save.settings.quality = tab.dataset.quality as Quality;
        this.persist();
        this.render();
      });
    });

    document.querySelector<HTMLSelectElement>('#languageSelect')?.addEventListener('change', (event) => {
      this.state.save.settings.language = (event.target as HTMLSelectElement).value as Language;
      this.persist();
    });
  }

  private ensureBootSequence() {
    if (this.state.bootReady || this.bootTimer) {
      return;
    }

    const duration = this.state.save.settings.lowMotion ? 1000 : BOOT_DURATION_MS;
    this.startBootFrames(duration);

    this.bootTimer = window.setTimeout(() => {
      this.bootTimer = 0;

      if (this.state.scene !== 'boot') {
        return;
      }

      this.state.bootReady = true;
      this.render();
    }, duration);
  }

  private clearBootSequence() {
    if (!this.bootTimer) {
      this.stopBootFrames();
      return;
    }

    window.clearTimeout(this.bootTimer);
    this.bootTimer = 0;
    this.stopBootFrames();
  }

  private resetBootSequence() {
    this.clearBootSequence();
    this.state.bootReady = false;
  }

  private setScene(next: Scene) {
    if (this.state.scene === 'boot' && next !== 'boot') {
      this.clearBootSequence();
    }

    if (next === 'boot') {
      this.resetBootSequence();
    }

    this.state.confirmMode = null;
    this.state.scene = next;
    this.render();
  }

  private persist() {
    persistSave(this.state.save);
  }

  private openSettings() {
    this.state.settingsOpen = true;
    this.state.confirmMode = null;
    this.render();
  }

  private closeSettings() {
    this.state.settingsOpen = false;
    this.state.confirmMode = null;
    this.render();
  }

  private confirmSettingsAction() {
    if (this.state.confirmMode === 'resetName') {
      this.state.save.playerName = DEFAULT_NAME;
      this.state.save.hasNamed = false;
      this.persist();
      this.state.settingsOpen = false;
      this.state.confirmMode = null;
      this.setScene('naming');
      return;
    }

    if (this.state.confirmMode === 'resetSettings') {
      this.state.save.settings = createDefaultSave().settings;
      this.persist();
    }

    this.state.confirmMode = null;
    this.render();
  }

  private randomizeName() {
    const name = RANDOM_NAMES[Math.floor(Math.random() * RANDOM_NAMES.length)];
    this.setNameInput(name);
  }

  private setNameInput(value: string) {
    const input = document.querySelector<HTMLInputElement>('#playerNameInput');

    if (input) {
      input.value = value;
    }
  }

  private submitName() {
    const input = document.querySelector<HTMLInputElement>('#playerNameInput');
    const error = document.querySelector<HTMLElement>('#nameError');
    const value = input?.value.trim() ?? '';
    const valid = /^[\u4e00-\u9fa5A-Za-z0-9 ]{1,12}$/.test(value) && [...value].length <= 12;

    if (!valid) {
      if (error) {
        error.textContent = '名字需要 1-12 个中英文或数字。';
      }

      return;
    }

    if (error) {
      error.textContent = '';
    }

    this.state.save.playerName = value;
    this.state.save.hasNamed = true;
    this.persist();
    this.setScene('mainMenu');
  }

  private onGameComplete(snapshot: GameSnapshot) {
    if (!snapshot.completed) {
      return;
    }

    this.state.save.lastLevel = 'valley';
    this.state.save.levels.valley.completed = true;
    this.state.save.levels.valley.bestStars = 3;
    this.state.save.gallery.moss = true;
    this.state.save.gallery.vine = true;
    this.persist();

    window.setTimeout(() => {
      this.setScene('result');
    }, 700);
  }

  private showToast(message: string) {
    this.root.querySelector('.toast')?.remove();

    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = message;
    this.root.appendChild(toast);

    window.setTimeout(() => toast.remove(), 1800);
  }

  private destroyGame() {
    this.game?.destroy();
    this.game = null;
  }

  private startBootFrames(duration: number) {
    this.stopBootFrames();

    const frame = document.querySelector<HTMLImageElement>('#startupLoadingFrame');
    if (!frame) {
      return;
    }

    const framePaths = STARTUP_LOADING_FRAME_FILES.map((filename) =>
      asset(`${STARTUP_ASSET_ROOT}/02_ui_loading/04-ui_loading_bar_fill_waterlux_frames/${filename}`)
    );

    let index = 0;
    frame.src = framePaths[0];

    if (this.state.save.settings.lowMotion) {
      frame.src = framePaths[framePaths.length - 1];
      return;
    }

    const stepMs = Math.max(48, Math.round(duration / framePaths.length));

    this.bootFrameTimer = window.setInterval(() => {
      index = Math.min(index + 1, framePaths.length - 1);
      frame.src = framePaths[index];

      if (index >= framePaths.length - 1) {
        this.stopBootFrames();
      }
    }, stepMs);
  }

  private stopBootFrames() {
    if (!this.bootFrameTimer) {
      return;
    }

    window.clearInterval(this.bootFrameTimer);
    this.bootFrameTimer = 0;
  }

  private handleResize = () => {
    this.render();
  };

  private viewportMode() {
    return window.innerWidth < window.innerHeight ? 'cover' : 'contain';
  }

  private viewportScale() {
    const widthScale = window.innerWidth / 1280;
    const heightScale = window.innerHeight / 720;

    return this.viewportMode() === 'cover' ? Math.max(widthScale, heightScale) : Math.min(widthScale, heightScale);
  }
}
