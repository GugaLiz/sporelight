import { getLevel, mechanismName, totalSpores, type WorldNode } from './levels';
import { GameModel, type RunState } from './model';
import type { GameSnapshot, SaveData } from '../types';

export class CanvasGame {
  readonly model: GameModel;
  private ctx: CanvasRenderingContext2D;
  private images = new Map<string, HTMLImageElement>();
  private raf = 0;
  private last = 0;
  private clock = 0;
  private paused = false;
  private disposed = false;
  private reported = false;
  private route: string[] = [];
  private travel: { from: WorldNode; to: WorldNode; progress: number; jump: boolean } | null = null;
  private hintNode: string | undefined;
  private glowUntil = 0;
  private settings: SaveData['settings'];
  private handlers: (() => void)[] = [];
  private tip: HTMLElement | null;

  constructor(private canvas: HTMLCanvasElement, levelId: string, saved: RunState | null,
    settings: SaveData['settings'], private onChange: (run: RunState) => void,
    private complete: (snapshot: GameSnapshot) => void,
    private sound: (kind: 'move' | 'grow' | 'collect' | 'complete') => void) {
    this.model = new GameModel(getLevel(levelId), saved);
    this.settings = settings;
    this.ctx = canvas.getContext('2d')!;
    this.tip = document.getElementById('gameTip');
    const keys = ['idle1', 'idle2', 'idle3', 'roll1', 'roll2', 'roll3', 'sow1', 'sow2', 'sow3', 'soil', 'flower', 'bloom', 'moss', 'light', 'vine', 'bridge', 'lily', 'lily-open', 'spore', 'bug', 'ring', 'arch'];
    keys.forEach(key => { const img = new Image(); img.src = `/images/production/${key}.png`; this.images.set(key, img); });
    const bg = new Image(); bg.src = `/images/production/bg-${this.model.level.chapter}.jpg`; this.images.set('bg', bg);
    for (const button of document.querySelectorAll<HTMLButtonElement>('[data-node]')) {
      const click = () => this.walkTo(button.dataset.node!);
      button.addEventListener('click', click); this.handlers.push(() => button.removeEventListener('click', click));
    }
    window.addEventListener('keydown', this.onKey);
    this.configure(settings);
    this.refreshHUD();
    this.raf = requestAnimationFrame(this.loop);
  }
  configure(settings: SaveData['settings']) {
    this.settings = settings;
    const ratio = settings.quality === 'hd' ? Math.min(window.devicePixelRatio || 1, 2) : settings.quality === 'soft' ? .8 : 1;
    this.canvas.width = 1280 * ratio; this.canvas.height = 720 * ratio;
    this.ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
  }
  pause(paused: boolean) { this.paused = paused; this.last = 0; }
  destroy() {
    this.disposed = true; cancelAnimationFrame(this.raf);
    window.removeEventListener('keydown', this.onKey); this.handlers.forEach(fn => fn());
  }
  sow() {
    if (this.paused || this.travel || this.model.state.completed) return;
    const before = this.model.state.activated.length;
    const result = this.model.interact(this.clock, this.settings.lowMotion);
    this.say(result.message);
    if (result.ok) {
      this.glowUntil = this.clock + 1100; this.sound('grow');
      if (this.settings.vibration && this.model.state.activated.length > before) navigator.vibrate?.(20);
      this.changed();
    }
  }
  undo() {
    if (this.paused || this.model.state.completed) return;
    this.route = []; this.travel = null;
    if (this.model.undo()) { this.say('轻轻退回一步，微光还在。'); this.changed(); }
    else this.say('还没有需要撤销的脚步。');
  }
  hint() { const hint = this.model.hint(); this.hintNode = hint.node; this.say(hint.message); }
  walkTo(id: string) {
    if (this.paused || this.model.state.completed) return;
    if (this.travel) return;
    if (id === this.model.state.node) { this.sow(); return; }
    const path = this.model.pathTo(id);
    if (!path) { this.hint(); return; }
    this.hintNode = undefined; this.route = path.slice(1); this.advance();
  }
  private advance() {
    const id = this.route.shift(); if (!id || this.model.state.completed) return;
    const to = this.model.level.nodes.find(n => n.id === id)!;
    const from = this.model.current;
    if (!this.model.edgeOpen(from.id, to.id)) { this.route = []; return; }
    this.travel = { from, to, progress: 0, jump: ['lily', 'rhythm'].includes(from.mechanism ?? '') && this.model.state.activated.includes(from.id) };
    this.sound('move');
  }
  private onKey = (event: KeyboardEvent) => {
    if (this.paused || event.repeat || (event.target instanceof HTMLElement && event.target.matches('input,select,textarea'))) return;
    if (event.key.toLowerCase() === 'e') { event.preventDefault(); this.sow(); return; }
    const directions: Record<string, [number, number]> = { ArrowLeft: [-1, 0], a: [-1, 0], ArrowRight: [1, 0], d: [1, 0], ArrowUp: [0, -1], w: [0, -1], ArrowDown: [0, 1], s: [0, 1] };
    const direction = directions[event.key]; if (!direction) return;
    event.preventDefault();
    const current = this.model.current;
    const next = this.model.level.nodes.filter(n => this.model.edgeOpen(current.id, n.id)).map(n => ({ node: n, score: ((n.x - current.x) * direction[0] + (n.y - current.y) * direction[1]) / Math.hypot(n.x - current.x, n.y - current.y) })).filter(n => n.score > .1).sort((a, b) => b.score - a.score)[0];
    if (next) this.walkTo(next.node.id);
  };
  private changed() { this.refreshHUD(); this.onChange(this.model.snapshot()); }
  private refreshHUD() {
    const count = document.getElementById('sporeCount'); if (count) count.textContent = `${this.model.state.collected.length} / ${totalSpores(this.model.level)}`;
    const grown = document.getElementById('grownCount'); if (grown) grown.textContent = `${this.model.state.activated.length} / ${this.model.level.nodes.filter(n => n.mechanism).length}`;
    const undo = document.querySelector<HTMLButtonElement>('[data-action="撤销"]'); if (undo) undo.disabled = !this.model.canUndo;
    const action = document.querySelector<HTMLButtonElement>('[data-action="播种"]');
    if (action) action.textContent = this.model.current.mechanism === 'reflect' && !this.model.state.activated.includes(this.model.state.node) ? '↻  旋转反光叶 · E' : '✧  播种 / 互动 · E';
    for (const button of document.querySelectorAll<HTMLButtonElement>('[data-node]')) {
      const node = this.model.level.nodes.find(n => n.id === button.dataset.node)!;
      const active = this.model.state.activated.includes(node.id);
      const current = node.id === this.model.state.node;
      const text = node.id === this.model.level.exit ? '唤醒终点花苞' : node.mechanism ? `${node.order ? `${node.order} · ` : ''}${mechanismName[node.mechanism]}` : node.id === 'start' ? '起点' : '微光石台';
      button.setAttribute('aria-label', `${text}${current ? '，当前位置，点击互动' : '，点击移动'}${active ? '，已唤醒' : ''}${node.spore && !this.model.state.collected.includes(node.id) ? '，有孢子' : ''}`);
      button.setAttribute('aria-current', current ? 'location' : 'false');
      button.dataset.reachable = String(!!this.model.pathTo(node.id));
    }
  }
  private say(message: string) { if (this.tip) this.tip.textContent = message; }
  private loop = (time: number) => {
    if (this.disposed) return;
    const dt = this.last ? Math.min(50, time - this.last) : 0; this.last = time;
    if (!this.paused && !document.hidden) {
      this.clock += dt;
      if (this.travel) {
        this.travel.progress = Math.min(1, this.travel.progress + dt / (this.settings.lowMotion ? 100 : 530));
        if (this.travel.progress === 1) {
          const previous = this.model.state.collected.length;
          const result = this.model.move(this.travel.to.id); this.travel = null;
          this.say(result.message); this.changed();
          if (this.model.state.collected.length > previous) this.sound('collect');
          if (!result.ok) this.route = [];
          if (this.model.state.completed && !this.reported) {
            this.reported = true; this.sound('complete');
            this.complete({ completed: true, levelId: this.model.level.id, seeds: this.model.level.nodes.filter(n => n.mechanism).map(n => this.model.state.activated.includes(n.id)), collected: this.model.state.collected.length, total: totalSpores(this.model.level), stars: this.model.stars, awakened: this.model.state.activated.length });
          } else this.advance();
        }
      }
    }
    this.draw(); this.raf = requestAnimationFrame(this.loop);
  };
  private sprite(key: string, x: number, y: number, size: number, alpha = 1) {
    const img = this.images.get(key); if (!img?.complete || !img.naturalWidth) return;
    this.ctx.save(); this.ctx.globalAlpha = alpha; this.ctx.drawImage(img, x - size / 2, y - size * .90625, size, size); this.ctx.restore();
  }
  private draw() {
    const ctx = this.ctx; const { level, state } = this.model;
    const night = level.chapter === 'cave'; const t = this.settings.lowMotion ? 0 : this.clock;
    ctx.clearRect(0, 0, 1280, 720);
    const bg = this.images.get('bg');
    ctx.fillStyle = night ? '#272e43' : '#9fae93'; ctx.fillRect(0, 0, 1280, 720);
    if (bg?.complete && bg.naturalWidth) ctx.drawImage(bg, 0, 0, 1280, 720);
    ctx.fillStyle = night ? 'rgba(19,26,49,.32)' : 'rgba(233,236,214,.62)'; ctx.fillRect(0, 0, 1280, 720);
    const wash = ctx.createLinearGradient(0, 80, 0, 670);
    wash.addColorStop(0, night ? '#202a42cc' : '#eff1dfbb'); wash.addColorStop(.5, night ? '#26334f88' : '#d2ddc5aa'); wash.addColorStop(1, night ? '#182139cc' : '#577b6b99');
    ctx.fillStyle = wash; ctx.fillRect(0, 0, 1280, 720);
    // Actual traversable connections are rendered separately from the scenery.
    level.edges.forEach(edge => {
      const a = level.nodes.find(n => n.id === edge.from)!; const b = level.nodes.find(n => n.id === edge.to)!;
      const open = this.model.edgeOpen(a.id, b.id);
      ctx.save(); ctx.lineCap = 'round'; ctx.setLineDash(open ? [] : [4, 14]);
      ctx.lineWidth = open ? 25 : 3; ctx.strokeStyle = open ? (night ? '#7979a0' : '#8c9e79') : (night ? '#788ba977' : '#6e846e77');
      ctx.beginPath(); ctx.moveTo(a.x, a.y + 17); ctx.lineTo(b.x, b.y + 17); ctx.stroke();
      if (open) { ctx.lineWidth = 17; ctx.strokeStyle = night ? '#b1abb8' : '#d9d7ae'; ctx.stroke(); }
      ctx.restore();
    });
    level.nodes.forEach(node => {
      const active = state.activated.includes(node.id); const visible = !!this.model.pathTo(node.id);
      // Layered rounded islands give the playable route a clear, separate silhouette.
      ctx.save(); ctx.globalAlpha = visible ? 1 : .63;
      ctx.fillStyle = night ? '#414d6c' : '#77846c'; ctx.beginPath(); ctx.ellipse(node.x, node.y + 25, 69, 31, 0, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = night ? '#73819c' : '#b9c6a0'; ctx.beginPath(); ctx.ellipse(node.x, node.y + 12, 69, 29, 0, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = night ? '#b4bdba66' : '#e9ebc788'; ctx.lineWidth = 2; ctx.stroke();
      ctx.fillStyle = night ? '#a9aeae' : '#e4dfba'; ctx.beginPath(); ctx.ellipse(node.x, node.y + 8, 50, 18, 0, 0, Math.PI * 2); ctx.fill();
      if (node.id === level.exit) this.sprite(state.completed ? 'bloom' : 'flower', node.x, node.y + 19, 155);
      else if (node.mechanism) {
        const sprites: Record<string, string> = { grow: active ? 'bloom' : 'soil', vine: active ? 'bridge' : 'vine', lily: active ? 'lily-open' : 'lily', rhythm: active ? 'lily-open' : 'lily', reflect: 'lily-open', light: active ? 'light' : 'moss', friend: active ? 'bloom' : 'soil', sequence: active ? 'light' : 'moss' };
        this.sprite(sprites[node.mechanism], node.x, node.y + 17, 115);
        if (node.mechanism === 'reflect') {
          const correct = active || (state.angles[node.id] ?? 0) === node.angle;
          const nextEdge = level.edges.find(e => e.gate === node.id);
          const destination = level.nodes.find(n => n.id === nextEdge?.to);
          const angle = correct && destination ? Math.atan2(destination.y - node.y, destination.x - node.x) : [-1.9, -.9, .25][state.angles[node.id] ?? 0];
          ctx.strokeStyle = correct ? '#ffecab' : '#f8e6b177'; ctx.lineWidth = correct ? 4 : 2;
          ctx.beginPath(); ctx.moveTo(node.x, node.y - 15); ctx.lineTo(node.x + Math.cos(angle) * 140, node.y - 15 + Math.sin(angle) * 140); ctx.stroke();
        }
        if (node.mechanism === 'rhythm' && !active) {
          const open = this.settings.lowMotion || this.clock % 3000 < 1500;
          ctx.strokeStyle = open ? '#b4f4ef' : '#718e9a'; ctx.lineWidth = 4; ctx.beginPath(); ctx.ellipse(node.x, node.y, 56, 24, 0, 0, Math.PI * 2); ctx.stroke();
          this.label(open ? '水膜亮起 · 可播种' : '等待雨滴…', node.x, node.y + 58, night);
        } else this.label(node.order ? `${node.order} · ${active ? '已点亮' : '星光'}` : active ? '已唤醒' : mechanismName[node.mechanism], node.x, node.y + 58, night);
        if (active && node.mechanism === 'friend') this.sprite('bug', node.x + 40 + Math.sin(t / 700) * 16, node.y - 65, 58);
      }
      if (node.spore && !state.collected.includes(node.id)) {
        const sy = node.y - 79 + Math.sin(t / 400 + node.x) * 4;
        if (this.settings.dynamicLight) { ctx.shadowColor = '#ffdd80'; ctx.shadowBlur = 22; }
        ctx.fillStyle = '#fff1b2'; ctx.beginPath(); ctx.arc(node.x, sy, 9, 0, Math.PI * 2); ctx.fill(); ctx.shadowBlur = 0;
        this.sprite('spore', node.x, sy + 15, 45);
      }
      if (active && this.settings.dynamicLight) {
        const gradient = ctx.createRadialGradient(node.x, node.y, 0, node.x, node.y, 100);
        gradient.addColorStop(0, '#f7e7a42b'); gradient.addColorStop(1, '#f7e7a400'); ctx.fillStyle = gradient; ctx.fillRect(node.x - 100, node.y - 100, 200, 200);
      }
      if (node.id === this.hintNode) { ctx.strokeStyle = '#fff3ad'; ctx.lineWidth = 4; ctx.setLineDash([7, 7]); ctx.beginPath(); ctx.ellipse(node.x, node.y + 10, 78, 37, 0, 0, Math.PI * 2); ctx.stroke(); }
      ctx.restore();
    });
    let { x, y } = this.model.current;
    if (this.travel) { const p = this.travel.progress; const easing = p * p * (3 - 2 * p); x = this.travel.from.x + (this.travel.to.x - this.travel.from.x) * easing; y = this.travel.from.y + (this.travel.to.y - this.travel.from.y) * easing - (this.travel.jump && !this.settings.lowMotion ? Math.sin(p * Math.PI) * 85 : 0); }
    ctx.fillStyle = '#273a4033'; ctx.beginPath(); ctx.ellipse(x, y + 12, 24, 9, 0, 0, Math.PI * 2); ctx.fill();
    const pose = this.clock < this.glowUntil ? 'sow' : this.travel ? 'roll' : 'idle';
    const frame = this.settings.lowMotion ? 1 : 1 + Math.floor(t / (pose === 'idle' ? 360 : 140)) % 3;
    this.sprite(`${pose}${frame}`, x, y + 14, 108);
    if (this.clock < this.glowUntil && this.settings.dynamicLight) this.sprite('ring', x, y + 25, 145, .6);
    if (this.settings.particles) {
      for (let i = 0; i < (this.settings.quality === 'soft' ? 12 : 35); i++) {
        const px = (i * 137 + 90 + Math.sin(t / 4500 + i) * 17) % 1280;
        const py = (i * 79 + 160 - t / 65 % 540 + 540) % 540 + 100;
        ctx.globalAlpha = .2 + (Math.sin(t / 800 + i) + 1) * .22; ctx.fillStyle = '#fff1bc'; ctx.beginPath(); ctx.arc(px, py, i % 3 === 0 ? 2 : 1, 0, Math.PI * 2); ctx.fill();
      } ctx.globalAlpha = 1;
    }
  }
  private label(text: string, x: number, y: number, night: boolean) {
    const ctx = this.ctx; ctx.font = '14px "Microsoft YaHei", sans-serif'; ctx.textAlign = 'center';
    const width = ctx.measureText(text).width + 20; ctx.fillStyle = night ? '#26334edb' : '#f7f3dcdb';
    ctx.beginPath(); ctx.roundRect(x - width / 2, y - 15, width, 24, 12); ctx.fill(); ctx.fillStyle = night ? '#efe8cd' : '#52664f'; ctx.fillText(text, x, y + 2);
  }
}
