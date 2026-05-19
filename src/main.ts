import './styles.css';

type Scene = 'boot' | 'naming' | 'mainMenu' | 'levelSelect' | 'game' | 'result' | 'gallery';
type Quality = 'soft' | 'standard' | 'hd';
type Language = 'zh-CN' | 'zh-TW' | 'en';

interface LevelSave {
  unlocked: boolean;
  completed: boolean;
  bestStars: number;
}

interface SaveData {
  playerName: string;
  hasNamed: boolean;
  lastLevel: string;
  levels: Record<'valley' | 'pond' | 'cave', LevelSave>;
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

interface GameSnapshot {
  completed: boolean;
  seeds: boolean[];
}

const SAVE_KEY = 'sporelight.save.v1';
const DEFAULT_NAME = '露薇';
const COMPLETE = '/images/sporelight_complete_assets_png';
const NAMING = '/images/sporelight_naming_page_assets';

const app = document.querySelector<HTMLDivElement>('#app');

if (!app) {
  throw new Error('Missing #app root');
}

const defaultSave = (): SaveData => ({
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
});

let save = loadSave();
let scene: Scene = save.hasNamed ? 'mainMenu' : 'boot';
let settingsOpen = false;
let confirmMode: 'resetName' | 'resetSettings' | null = null;
let game: CanvasGame | null = null;

function loadSave(): SaveData {
  try {
    const raw = localStorage.getItem(SAVE_KEY);
    if (!raw) return defaultSave();
    const parsed = JSON.parse(raw) as Partial<SaveData>;
    return mergeSave(defaultSave(), parsed);
  } catch {
    return defaultSave();
  }
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

function persist() {
  localStorage.setItem(SAVE_KEY, JSON.stringify(save));
}

function setScene(next: Scene) {
  game?.destroy();
  game = null;
  scene = next;
  render();
}

function asset(path: string) {
  return path;
}

function button(label: string, className: string, onClick: () => void, disabled = false) {
  return `<button class="asset-button ${className}" ${disabled ? 'disabled' : ''} data-action="${label}"><span>${label}</span></button>`;
}

function bindButtons(handlers: Record<string, () => void>) {
  Object.entries(handlers).forEach(([key, handler]) => {
    document.querySelectorAll<HTMLElement>(`[data-action="${key}"]`).forEach((element) => {
      element.addEventListener('click', handler);
    });
  });
}

function render() {
  app.innerHTML = `<main class="shell"><section class="stage">${renderScene()}</section>${settingsOpen ? renderSettings() : ''}</main>`;
  bindScene();
  if (settingsOpen) bindSettings();
}

function renderScene() {
  switch (scene) {
    case 'boot':
      return renderBoot();
    case 'naming':
      return renderNaming();
    case 'mainMenu':
      return renderMainMenu();
    case 'levelSelect':
      return renderLevelSelect();
    case 'game':
      return renderGame();
    case 'result':
      return renderResult();
    case 'gallery':
      return renderGallery();
  }
}

function renderBoot() {
  return `
    <div class="screen boot-screen" style="background-image:url('${asset(`${COMPLETE}/backgrounds/bg_mainmenu.png`)}')">
      <img class="parallax far" src="${asset(`${COMPLETE}/backgrounds/bg_mountain_far.png`)}" alt="" />
      <img class="parallax mid" src="${asset(`${COMPLETE}/backgrounds/bg_mountain_mid.png`)}" alt="" />
      <img class="clouds" src="${asset(`${COMPLETE}/backgrounds/bg_clouds.png`)}" alt="" />
      <img class="logo boot-logo" src="${asset(`${COMPLETE}/ui/logo/ui_logo_cn_en.png`)}" alt="微光苔原 Sporelight" />
      <img class="boot-luvie" src="${asset(`${COMPLETE}/characters/char_luvie_idle_02.png`)}" alt="" />
      <button class="tap-start" data-action="enterBoot">点击进入</button>
    </div>
  `;
}

function renderNaming() {
  return `
    <div class="screen naming-screen" style="background-image:url('${asset(`${NAMING}/backgrounds/bg_naming.png`)}')">
      <img class="naming-overlay" src="${asset(`${NAMING}/backgrounds/bg_naming_overlay.png`)}" alt="" />
      <img class="naming-logo" src="${asset(`${NAMING}/ui/logo/ui_logo_naming.png`)}" alt="微光苔原" />
      <img class="naming-title" src="${asset(`${NAMING}/ui/logo/ui_title_naming.png`)}" alt="为主角命名" />
      <img class="naming-luvie" src="${asset(`${NAMING}/characters/char_luvie_naming.png`)}" alt="" />
      <div class="name-card">
        <p>她从微光中醒来。</p>
        <p>你想怎么称呼她？</p>
        <label class="name-input-wrap">
          <input id="playerNameInput" maxlength="12" value="${escapeHtml(save.playerName || DEFAULT_NAME)}" />
        </label>
        <p id="nameError" class="form-error" aria-live="polite"></p>
        <div class="naming-actions">
          <button class="small-gem" data-action="randomName">随机名字</button>
          <button class="small-gem" data-action="resetNameField">恢复默认</button>
        </div>
        <button class="primary-gem" data-action="startJourney">开始旅程</button>
      </div>
    </div>
  `;
}

function renderMainMenu() {
  return `
    <div class="screen menu-screen" style="background-image:url('${asset(`${COMPLETE}/backgrounds/bg_mainmenu.png`)}')">
      <img class="clouds" src="${asset(`${COMPLETE}/backgrounds/bg_clouds.png`)}" alt="" />
      <img class="logo menu-logo" src="${asset(`${COMPLETE}/ui/logo/ui_logo_cn_en.png`)}" alt="微光苔原 Sporelight" />
      <div class="menu-player">欢迎回来，${escapeHtml(save.playerName)}</div>
      <nav class="menu-actions">
        ${button('开始游戏', 'btn-start', () => undefined)}
        ${button('继续旅程', 'btn-continue', () => undefined, !save.levels.valley.completed && save.lastLevel !== 'valley')}
        ${button('图鉴', 'btn-gallery', () => undefined)}
        ${button('设置', 'btn-settings', () => undefined)}
      </nav>
    </div>
  `;
}

function renderLevelSelect() {
  const levels = [
    { id: 'valley', title: '1-1 苔藓山谷', desc: '播下微光，让苔藓重新连成小路。', bg: 'bg_valley.png' },
    { id: 'pond', title: '1-2 雨滴池塘', desc: '睡莲还在等待下一阵雨。', bg: 'bg_pond.png' },
    { id: 'cave', title: '1-3 星光洞穴', desc: '洞穴深处的星光仍未醒来。', bg: 'bg_cave.png' }
  ] as const;

  return `
    <div class="screen level-screen" style="background-image:url('${asset(`${COMPLETE}/backgrounds/bg_level_select.png`)}')">
      <button class="round-nav back" data-action="返回主菜单">返回</button>
      <button class="round-nav settings" data-action="设置">设置</button>
      <h1>选择旅程</h1>
      <div class="level-grid">
        ${levels
          .map((level) => {
            const data = save.levels[level.id];
            return `
              <article class="level-card ${data.unlocked ? 'unlocked' : 'locked'}">
                <img src="${asset(`${COMPLETE}/backgrounds/${level.bg}`)}" alt="" />
                <div class="level-shade"></div>
                <h2>${level.title}</h2>
                <p>${level.desc}</p>
                <div class="level-state">${data.completed ? '已完成' : data.unlocked ? '可进入' : '锁定'}</div>
                <button class="level-enter" data-action="${data.unlocked ? '进入苔藓山谷' : '锁定关卡'}">${data.unlocked ? '进入关卡' : '尚未开放'}</button>
              </article>
            `;
          })
          .join('')}
      </div>
    </div>
  `;
}

function renderGame() {
  return `
    <div class="screen game-screen">
      <canvas id="gameCanvas" width="1280" height="720" aria-label="苔藓山谷"></canvas>
      <div class="game-hud">
        <button class="hud-button" data-action="返回关卡选择">返回</button>
        <div class="hud-title">苔藓山谷</div>
        <button class="hud-button" data-action="设置">设置</button>
      </div>
      <div class="game-tip" id="gameTip">点击地面移动，靠近土壤后按 E 或点击播种。</div>
      <div class="game-actions">
        <button class="skill-button" data-action="播种">播种</button>
      </div>
    </div>
  `;
}

function renderResult() {
  return `
    <div class="screen result-screen" style="background-image:url('${asset(`${COMPLETE}/backgrounds/bg_valley.png`)}')">
      <div class="result-panel">
        <img src="${asset(`${COMPLETE}/characters/char_luvie_bow_02.png`)}" alt="" />
        <h1>苔藓山谷重新发光了</h1>
        <p>${escapeHtml(save.playerName)}播下的孢子长成了新的路。</p>
        <div class="unlock-row">
          <span>解锁图鉴</span>
          <strong>发光苔藓</strong>
          <strong>藤蔓桥</strong>
        </div>
        <div class="result-actions">
          <button class="primary-gem" data-action="返回关卡选择">关卡选择</button>
          <button class="small-gem" data-action="重玩">重玩</button>
          <button class="small-gem" data-action="图鉴">图鉴</button>
        </div>
      </div>
    </div>
  `;
}

function renderGallery() {
  const items = [
    ['flowerbud', '萌芽花台', '沉睡的花苞会在微光里慢慢舒展。', 'gallery_flowerbud.png'],
    ['moss', '发光苔藓', '在暗处储存微光，愿意替旅人照亮脚边。', 'gallery_moss.png'],
    ['vine', '藤蔓桥', '从一粒孢子伸展成路，连接原本不能抵达的地方。', 'gallery_vine.png'],
    ['bug', '发光小虫', '喜欢温暖的光，会绕着新生植物跳舞。', 'gallery_bug_glow.png'],
    ['lilypad', '睡莲', '安静浮在水面，醒来时会送出一串水珠。', 'gallery_lilypad.png'],
    ['mushroom', '光菇', '在洞穴里亮起，像一小盏不需要火的灯。', 'gallery_mushroom_light.png'],
    ['arch', '遗迹拱门', '旧石头记得很久以前的回声。', 'gallery_ruin_arch.png'],
    ['starflower', '星花', '只在被温柔照亮的夜里开放。', 'gallery_starflower.png']
  ];

  return `
    <div class="screen gallery-screen" style="background-image:url('${asset(`${COMPLETE}/backgrounds/bg_gallery.png`)}')">
      <button class="round-nav back" data-action="返回主菜单">返回</button>
      <button class="round-nav settings" data-action="设置">设置</button>
      <h1>微光图鉴</h1>
      <div class="gallery-grid">
        ${items
          .map(([id, title, desc, image]) => {
            const unlocked = Boolean(save.gallery[id]);
            return `
              <article class="gallery-card ${unlocked ? 'unlocked' : 'locked'}">
                <div class="gallery-art">
                  <img src="${asset(`${COMPLETE}/gallery/${unlocked ? image : 'gallery_card_normal.png'}`)}" alt="" />
                </div>
                <h2>${unlocked ? title : '尚未发现'}</h2>
                <p>${unlocked ? desc : '旅程继续时，它会慢慢现身。'}</p>
              </article>
            `;
          })
          .join('')}
      </div>
    </div>
  `;
}

function renderSettings() {
  return `
    <div class="settings-layer" role="dialog" aria-modal="true">
      <div class="settings-modal">
        <button class="settings-close" data-action="关闭设置" aria-label="关闭设置"></button>
        <header class="settings-header">
          <h1><span>设置</span></h1>
          <p>Sporelight Settings</p>
        </header>
        <div class="settings-body">
          <aside class="settings-companion">
            <div class="settings-character-scene">
              <img class="settings-firefly" src="${asset(`${COMPLETE}/fx/fx_glow_critter.png`)}" alt="" />
              <img class="settings-luvie" src="${asset(`${COMPLETE}/characters/char_luvie_front.png`)}" alt="" />
              <img class="settings-platform" src="${asset(`${COMPLETE}/world/world_moss_bright.png`)}" alt="" />
            </div>
            <p class="settings-poem-text">在微光的陪伴下，<br />每一刻都将变得温柔而美好。</p>
            <div class="settings-ornament"></div>
          </aside>
          <div class="settings-content">
          <section class="settings-card audio-card">
            <h2><span>♪</span>音频<i></i></h2>
            ${settingsSlider('bgm', '背景音乐', save.settings.bgm, 'ui_icon_volume_music.png')}
            ${settingsSlider('sfx', '音效音量', save.settings.sfx, 'ui_icon_volume_sfx.png')}
            ${settingsSlider('ambient', '环境音', save.settings.ambient, 'ui_icon_volume_ambient.png')}
          </section>
          <section class="settings-card video-card">
            <h2><span>▣</span>画面<i></i></h2>
            <div class="settings-row">
              <span class="setting-label">画质</span>
              <div class="quality-tabs">
                ${qualityTab('soft', '柔和')}
                ${qualityTab('standard', '标准')}
                ${qualityTab('hd', '高清')}
              </div>
              <div class="settings-toggle-column">
                ${settingsToggle('dynamicLight', '动态光效', save.settings.dynamicLight)}
                ${settingsToggle('particles', '粒子效果', save.settings.particles)}
                ${settingsToggle('lowMotion', '低动态模式', save.settings.lowMotion)}
              </div>
            </div>
          </section>
          <section class="settings-card operation-card">
            <h2><span>☝</span>操作<i></i></h2>
            <div class="settings-row">
              <label class="language-row frequency-row">
                <span>提示频率</span>
                <select id="hintFrequencySelect">
                  <option>适中</option>
                  <option>较少</option>
                  <option>频繁</option>
                </select>
              </label>
              <div class="dialog-speed">
                <span>对话速度</span>
                <div class="quality-tabs">
                  <button type="button">舒缓</button>
                  <button type="button" class="active">标准</button>
                  <button type="button">快速</button>
                </div>
              </div>
              ${settingsToggle('vibration', '震动反馈', save.settings.vibration)}
            </div>
          </section>
          <section class="settings-card general-card">
            <h2><span>⚙</span>通用<i></i></h2>
            <div class="settings-row">
            <label class="language-row">
              <span>语言</span>
              <select id="languageSelect">
                <option value="zh-CN" ${save.settings.language === 'zh-CN' ? 'selected' : ''}>简体中文</option>
                <option value="zh-TW" ${save.settings.language === 'zh-TW' ? 'selected' : ''}>繁體中文</option>
                <option value="en" ${save.settings.language === 'en' ? 'selected' : ''}>English</option>
              </select>
            </label>
            ${settingsToggle('fullscreen', '全屏模式', save.settings.fullscreen)}
            <div class="settings-buttons">
              <button class="settings-sub-button" data-action="重置名称">重置角色名称</button>
              <button class="settings-sub-button" data-action="恢复默认设置">恢复默认设置</button>
            </div>
            </div>
          </section>
          </div>
        </div>
        <footer class="settings-footer">
          <button class="footer-button cancel" data-action="关闭设置">取消</button>
          <button class="footer-button restore" data-action="恢复默认设置">恢复默认</button>
          <button class="footer-button confirm" data-action="关闭设置">确认</button>
        </footer>
        <div class="settings-version">Ver 0.9.1</div>
        ${confirmMode ? renderConfirmDialog() : ''}
      </div>
    </div>
  `;
}

function settingsSlider(key: 'bgm' | 'sfx' | 'ambient', label: string, value: number, _icon: string) {
  return `
    <label class="settings-slider">
      <span>${label}</span>
      <input type="range" min="0" max="100" value="${Math.round(value * 100)}" data-setting-slider="${key}" />
      <em>${Math.round(value * 100)}%</em>
    </label>
  `;
}

function settingsToggle(key: keyof SaveData['settings'], label: string, active: boolean) {
  return `
    <button class="toggle-row ${active ? 'active' : ''}" data-setting-toggle="${key}">
      <span>${label}</span>
      <i></i>
    </button>
  `;
}

function qualityTab(value: Quality, label: string) {
  return `<button class="${save.settings.quality === value ? 'active' : ''}" data-quality="${value}">${label}</button>`;
}

function renderConfirmDialog() {
  const text = confirmMode === 'resetName' ? '将角色名称恢复为“露薇”？' : '将设置恢复为默认值？';
  return `
    <div class="confirm-mask">
      <div class="confirm-dialog">
        <p>${text}</p>
        <div>
          <button data-action="取消确认">取消</button>
          <button data-action="确认操作">确认</button>
        </div>
      </div>
    </div>
  `;
}

function bindScene() {
  bindButtons({
    enterBoot: () => setScene(save.hasNamed ? 'mainMenu' : 'naming'),
    randomName: randomizeName,
    resetNameField: () => setNameInput(DEFAULT_NAME),
    startJourney: submitName,
    开始游戏: () => setScene('levelSelect'),
    继续旅程: () => setScene('levelSelect'),
    图鉴: () => setScene('gallery'),
    设置: openSettings,
    返回主菜单: () => setScene('mainMenu'),
    返回关卡选择: () => setScene('levelSelect'),
    进入苔藓山谷: () => setScene('game'),
    锁定关卡: () => showToast('这片苔原还在沉睡。'),
    播种: () => game?.sow(),
    重玩: () => setScene('game')
  });

  if (scene === 'boot') {
    document.querySelector('.boot-screen')?.addEventListener('click', () => setScene(save.hasNamed ? 'mainMenu' : 'naming'), { once: true });
  }

  if (scene === 'game') {
    const canvas = document.querySelector<HTMLCanvasElement>('#gameCanvas');
    const tip = document.querySelector<HTMLElement>('#gameTip');
    if (canvas) {
      game = new CanvasGame(canvas, tip, onGameComplete);
    }
  }
}

function bindSettings() {
  bindButtons({
    关闭设置: closeSettings,
    重置名称: () => {
      confirmMode = 'resetName';
      render();
    },
    恢复默认设置: () => {
      confirmMode = 'resetSettings';
      render();
    },
    取消确认: () => {
      confirmMode = null;
      render();
    },
    确认操作: confirmSettingsAction
  });

  document.querySelectorAll<HTMLInputElement>('[data-setting-slider]').forEach((input) => {
    input.addEventListener('input', () => {
      const key = input.dataset.settingSlider as 'bgm' | 'sfx' | 'ambient';
      save.settings[key] = Number(input.value) / 100;
      input.closest('.settings-slider')?.querySelector('em')?.replaceChildren(`${input.value}%`);
      persist();
    });
  });

  document.querySelectorAll<HTMLButtonElement>('[data-setting-toggle]').forEach((toggle) => {
    toggle.addEventListener('click', () => {
      const key = toggle.dataset.settingToggle as keyof SaveData['settings'];
      const current = save.settings[key];
      if (typeof current === 'boolean') {
        save.settings[key] = !current as never;
        persist();
        render();
      }
    });
  });

  document.querySelectorAll<HTMLButtonElement>('[data-quality]').forEach((tab) => {
    tab.addEventListener('click', () => {
      save.settings.quality = tab.dataset.quality as Quality;
      persist();
      render();
    });
  });

  document.querySelector<HTMLSelectElement>('#languageSelect')?.addEventListener('change', (event) => {
    save.settings.language = (event.target as HTMLSelectElement).value as Language;
    persist();
  });
}

function openSettings() {
  settingsOpen = true;
  confirmMode = null;
  render();
}

function closeSettings() {
  settingsOpen = false;
  confirmMode = null;
  render();
}

function confirmSettingsAction() {
  if (confirmMode === 'resetName') {
    save.playerName = DEFAULT_NAME;
    save.hasNamed = false;
    persist();
    settingsOpen = false;
    confirmMode = null;
    setScene('naming');
    return;
  }
  if (confirmMode === 'resetSettings') {
    save.settings = defaultSave().settings;
    persist();
  }
  confirmMode = null;
  render();
}

function randomizeName() {
  const names = ['露薇', '茸茸', '小伞', '渺渺', '芽芽', '绯儿', '朵朵', '团子', '糯糯', '微光', '孢子', '苔米', '青苔', '露珠', '花崽', '绒球'];
  setNameInput(names[Math.floor(Math.random() * names.length)]);
}

function setNameInput(value: string) {
  const input = document.querySelector<HTMLInputElement>('#playerNameInput');
  if (input) input.value = value;
}

function submitName() {
  const input = document.querySelector<HTMLInputElement>('#playerNameInput');
  const error = document.querySelector<HTMLElement>('#nameError');
  const value = input?.value.trim() ?? '';
  const valid = /^[\u4e00-\u9fa5A-Za-z0-9 ]{1,12}$/.test(value) && [...value].length <= 12;
  if (!valid) {
    if (error) error.textContent = '名字需要 1-12 个中英文或数字。';
    return;
  }
  save.playerName = value;
  save.hasNamed = true;
  persist();
  setScene('mainMenu');
}

function onGameComplete(snapshot: GameSnapshot) {
  if (!snapshot.completed) return;
  save.lastLevel = 'valley';
  save.levels.valley.completed = true;
  save.levels.valley.bestStars = 3;
  save.gallery.moss = true;
  save.gallery.vine = true;
  persist();
  setTimeout(() => setScene('result'), 700);
}

function showToast(message: string) {
  const toast = document.createElement('div');
  toast.className = 'toast';
  toast.textContent = message;
  app.appendChild(toast);
  setTimeout(() => toast.remove(), 1800);
}

function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' })[char] ?? char);
}

class CanvasGame {
  private ctx: CanvasRenderingContext2D;
  private raf = 0;
  private destroyed = false;
  private keys = new Set<string>();
  private target: { x: number; y: number } | null = null;
  private player = { x: 170, y: 545, vx: 0, vy: 0, state: 'idle' as 'idle' | 'move' | 'sow' | 'done' };
  private seeds = [
    { x: 430, y: 475, grown: false, type: 'moss' as const },
    { x: 735, y: 392, grown: false, type: 'vine' as const }
  ];
  private exit = { x: 1060, y: 255, active: false };
  private images = new Map<string, HTMLImageElement>();
  private last = performance.now();
  private sowUntil = 0;
  private messageUntil = 0;

  constructor(
    private canvas: HTMLCanvasElement,
    private tip: HTMLElement | null,
    private complete: (snapshot: GameSnapshot) => void
  ) {
    const context = canvas.getContext('2d');
    if (!context) throw new Error('Canvas is not supported');
    this.ctx = context;
    this.loadImages();
    this.bind();
    this.loop(performance.now());
  }

  destroy() {
    this.destroyed = true;
    cancelAnimationFrame(this.raf);
    window.removeEventListener('keydown', this.onKeyDown);
    window.removeEventListener('keyup', this.onKeyUp);
  }

  sow() {
    const seed = this.nearSeed();
    if (!seed) {
      this.say('再靠近一点，孢子才听得到土地的声音。');
      return;
    }
    if (seed.grown) {
      this.say('这里已经亮起来了。');
      return;
    }
    seed.grown = true;
    this.player.state = 'sow';
    this.sowUntil = performance.now() + 900;
    this.exit.active = this.seeds.every((item) => item.grown);
    this.say(seed.type === 'moss' ? '苔藓醒来了。' : '藤蔓慢慢搭成了一座桥。');
  }

  private loadImages() {
    [
      ['bg', `${COMPLETE}/backgrounds/bg_valley.png`],
      ['idle1', `${COMPLETE}/characters/char_luvie_idle_01.png`],
      ['idle2', `${COMPLETE}/characters/char_luvie_idle_02.png`],
      ['idle3', `${COMPLETE}/characters/char_luvie_idle_03.png`],
      ['roll1', `${COMPLETE}/characters/char_luvie_roll_01.png`],
      ['roll2', `${COMPLETE}/characters/char_luvie_roll_02.png`],
      ['roll3', `${COMPLETE}/characters/char_luvie_roll_03.png`],
      ['sow1', `${COMPLETE}/characters/char_luvie_sow_01.png`],
      ['sow2', `${COMPLETE}/characters/char_luvie_sow_02.png`],
      ['sow3', `${COMPLETE}/characters/char_luvie_sow_03.png`],
      ['shadow', `${COMPLETE}/characters/char_luvie_shadow.png`],
      ['soil', `${COMPLETE}/world/world_soil_empty.png`],
      ['soilSowed', `${COMPLETE}/world/world_soil_sowed.png`],
      ['mossDark', `${COMPLETE}/world/world_moss_dark.png`],
      ['mossBright', `${COMPLETE}/world/world_moss_bright.png`],
      ['vineSeed', `${COMPLETE}/world/world_vine_seed.png`],
      ['vineBridge', `${COMPLETE}/world/world_vine_bridge.png`],
      ['trail', `${COMPLETE}/fx/fx_spore_trail.png`],
      ['ring', `${COMPLETE}/fx/fx_growth_ring.png`],
      ['ripple', `${COMPLETE}/fx/fx_click_ripple.png`]
    ].forEach(([key, src]) => {
      const image = new Image();
      image.src = src;
      this.images.set(key, image);
    });
  }

  private bind() {
    this.canvas.addEventListener('pointerdown', (event) => {
      const rect = this.canvas.getBoundingClientRect();
      const scaleX = this.canvas.width / rect.width;
      const scaleY = this.canvas.height / rect.height;
      this.target = {
        x: (event.clientX - rect.left) * scaleX,
        y: (event.clientY - rect.top) * scaleY
      };
      this.say('露薇轻轻滚了过去。');
    });
    window.addEventListener('keydown', this.onKeyDown);
    window.addEventListener('keyup', this.onKeyUp);
  }

  private onKeyDown = (event: KeyboardEvent) => {
    this.keys.add(event.key.toLowerCase());
    if (event.key.toLowerCase() === 'e') this.sow();
  };

  private onKeyUp = (event: KeyboardEvent) => {
    this.keys.delete(event.key.toLowerCase());
  };

  private loop = (time: number) => {
    if (this.destroyed) return;
    const delta = Math.min(0.04, (time - this.last) / 1000);
    this.last = time;
    this.update(delta, time);
    this.draw(time);
    this.raf = requestAnimationFrame(this.loop);
  };

  private update(delta: number, time: number) {
    if (this.player.state === 'sow' && time < this.sowUntil) return;
    if (this.player.state === 'sow') this.player.state = 'idle';

    let dx = 0;
    let dy = 0;
    if (this.keys.has('arrowleft') || this.keys.has('a')) dx -= 1;
    if (this.keys.has('arrowright') || this.keys.has('d')) dx += 1;
    if (this.keys.has('arrowup') || this.keys.has('w')) dy -= 1;
    if (this.keys.has('arrowdown') || this.keys.has('s')) dy += 1;

    if (dx || dy) {
      this.target = null;
      const length = Math.hypot(dx, dy);
      this.player.x += (dx / length) * 240 * delta;
      this.player.y += (dy / length) * 240 * delta;
    } else if (this.target) {
      const tx = this.target.x - this.player.x;
      const ty = this.target.y - this.player.y;
      const distance = Math.hypot(tx, ty);
      if (distance < 8) {
        this.target = null;
      } else {
        this.player.x += (tx / distance) * 230 * delta;
        this.player.y += (ty / distance) * 230 * delta;
      }
    }

    this.player.x = Math.max(95, Math.min(1150, this.player.x));
    this.player.y = Math.max(170, Math.min(610, this.player.y));
    this.player.state = dx || dy || this.target ? 'move' : 'idle';

    if (this.exit.active && Math.hypot(this.player.x - this.exit.x, this.player.y - this.exit.y) < 70) {
      this.player.state = 'done';
      this.complete({ completed: true, seeds: this.seeds.map((seed) => seed.grown) });
    }
  }

  private draw(time: number) {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, 1280, 720);
    this.drawImage('bg', 0, 0, 1280, 720);
    this.drawPath();
    this.drawSeeds(time);
    this.drawExit(time);
    this.drawPlayer(time);
  }

  private drawPath() {
    const ctx = this.ctx;
    ctx.save();
    ctx.globalAlpha = 0.68;
    ctx.lineWidth = 36;
    ctx.lineCap = 'round';
    ctx.strokeStyle = '#dbd6b5';
    ctx.beginPath();
    ctx.moveTo(170, 545);
    ctx.quadraticCurveTo(315, 510, 430, 475);
    ctx.quadraticCurveTo(590, 420, 735, 392);
    if (this.seeds[1].grown) {
      ctx.quadraticCurveTo(900, 340, 1060, 255);
    }
    ctx.stroke();
    ctx.restore();
  }

  private drawSeeds(time: number) {
    this.seeds.forEach((seed, index) => {
      const wobble = Math.sin(time / 340 + index) * 3;
      this.drawImage(seed.grown ? 'soilSowed' : 'soil', seed.x - 70, seed.y - 55 + wobble, 140, 105);
      if (seed.type === 'moss') {
        this.drawImage(seed.grown ? 'mossBright' : 'mossDark', seed.x - 90, seed.y - 110 + wobble, 180, 140);
      } else {
        this.drawImage(seed.grown ? 'vineBridge' : 'vineSeed', seed.x - 90, seed.y - 105 + wobble, 180, 120);
      }
      if (seed.grown) {
        this.ctx.globalAlpha = 0.5 + Math.sin(time / 220) * 0.15;
        this.drawImage('ring', seed.x - 90, seed.y - 85, 180, 140);
        this.ctx.globalAlpha = 1;
      }
    });
  }

  private drawExit(time: number) {
    const ctx = this.ctx;
    ctx.save();
    ctx.translate(this.exit.x, this.exit.y);
    const radius = this.exit.active ? 34 + Math.sin(time / 180) * 4 : 24;
    ctx.globalAlpha = this.exit.active ? 0.9 : 0.35;
    ctx.fillStyle = this.exit.active ? '#ffe59b' : '#c7c7bc';
    ctx.shadowBlur = this.exit.active ? 24 : 8;
    ctx.shadowColor = '#ffe59b';
    ctx.beginPath();
    ctx.arc(0, 0, radius, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  private drawPlayer(time: number) {
    const moving = this.player.state === 'move';
    if (moving) {
      this.drawImage('trail', this.player.x - 95, this.player.y - 68, 150, 105);
    }
    this.drawImage('shadow', this.player.x - 55, this.player.y + 42, 110, 36);
    const frame = this.frameFor(time);
    const size = this.player.state === 'sow' ? 160 : 130;
    this.drawImage(frame, this.player.x - size / 2, this.player.y - size / 2, size, size);
  }

  private frameFor(time: number) {
    if (this.player.state === 'sow') {
      const frames = ['sow1', 'sow2', 'sow3'];
      return frames[Math.floor((time / 160) % frames.length)];
    }
    if (this.player.state === 'move') {
      const frames = ['roll1', 'roll2', 'roll3'];
      return frames[Math.floor((time / 120) % frames.length)];
    }
    const frames = ['idle1', 'idle2', 'idle3', 'idle2'];
    return frames[Math.floor((time / 280) % frames.length)];
  }

  private drawImage(key: string, x: number, y: number, width: number, height: number) {
    const image = this.images.get(key);
    if (image?.complete && image.naturalWidth) {
      this.ctx.drawImage(image, x, y, width, height);
      return;
    }
    this.ctx.fillStyle = '#f4d6ae';
    this.ctx.fillRect(x, y, width, height);
  }

  private nearSeed() {
    return this.seeds.find((seed) => Math.hypot(this.player.x - seed.x, this.player.y - seed.y) < 95);
  }

  private say(message: string) {
    this.messageUntil = performance.now() + 2200;
    if (this.tip) {
      this.tip.textContent = message;
      window.setTimeout(() => {
        if (performance.now() > this.messageUntil && this.tip) {
          this.tip.textContent = '点击地面移动，靠近土壤后按 E 或点击播种。';
        }
      }, 2300);
    }
  }
}

render();
