import { asset } from '../assets';
import { COMPLETE_ASSET_ROOT, GAME_DEFAULT_TIP } from '../constants';
import type { GameSnapshot } from '../types';

const COMPLETE = COMPLETE_ASSET_ROOT;

type Seed = {
  x: number;
  y: number;
  grown: boolean;
  type: 'moss' | 'vine';
};

export class CanvasGame {
  private readonly ctx: CanvasRenderingContext2D;
  private raf = 0;
  private destroyed = false;
  private completed = false;
  private keys = new Set<string>();
  private target: { x: number; y: number } | null = null;
  private player = { x: 170, y: 545, state: 'idle' as 'idle' | 'move' | 'sow' | 'done' };
  private seeds: Seed[] = [
    { x: 430, y: 475, grown: false, type: 'moss' },
    { x: 735, y: 392, grown: false, type: 'vine' }
  ];
  private exit = { x: 1060, y: 255, active: false };
  private images = new Map<string, HTMLImageElement>();
  private last = performance.now();
  private sowUntil = 0;
  private messageUntil = 0;

  constructor(
    private readonly canvas: HTMLCanvasElement,
    private readonly tip: HTMLElement | null,
    private readonly complete: (snapshot: GameSnapshot) => void
  ) {
    const context = canvas.getContext('2d');

    if (!context) {
      throw new Error('Canvas is not supported');
    }

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
      ['ring', `${COMPLETE}/fx/fx_growth_ring.png`]
    ].forEach(([key, src]) => {
      const image = new Image();
      image.src = asset(src);
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

    if (event.key.toLowerCase() === 'e') {
      this.sow();
    }
  };

  private onKeyUp = (event: KeyboardEvent) => {
    this.keys.delete(event.key.toLowerCase());
  };

  private loop = (time: number) => {
    if (this.destroyed) {
      return;
    }

    const delta = Math.min(0.04, (time - this.last) / 1000);
    this.last = time;

    this.update(delta, time);
    this.draw(time);

    this.raf = requestAnimationFrame(this.loop);
  };

  private update(delta: number, time: number) {
    if (this.player.state === 'sow' && time < this.sowUntil) {
      return;
    }

    if (this.player.state === 'sow') {
      this.player.state = 'idle';
    }

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

    if (!this.completed && this.exit.active && Math.hypot(this.player.x - this.exit.x, this.player.y - this.exit.y) < 70) {
      this.completed = true;
      this.player.state = 'done';
      this.complete({ completed: true, seeds: this.seeds.map((seed) => seed.grown) });
    }
  }

  private draw(time: number) {
    this.ctx.clearRect(0, 0, 1280, 720);
    this.drawImage('bg', 0, 0, 1280, 720);
    this.drawPath();
    this.drawSeeds(time);
    this.drawExit(time);
    this.drawPlayer(time);
  }

  private drawPath() {
    this.ctx.save();
    this.ctx.globalAlpha = 0.68;
    this.ctx.lineWidth = 36;
    this.ctx.lineCap = 'round';
    this.ctx.strokeStyle = '#dbd6b5';
    this.ctx.beginPath();
    this.ctx.moveTo(170, 545);
    this.ctx.quadraticCurveTo(315, 510, 430, 475);
    this.ctx.quadraticCurveTo(590, 420, 735, 392);

    if (this.seeds[1].grown) {
      this.ctx.quadraticCurveTo(900, 340, 1060, 255);
    }

    this.ctx.stroke();
    this.ctx.restore();
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
    this.ctx.save();
    this.ctx.translate(this.exit.x, this.exit.y);

    const radius = this.exit.active ? 34 + Math.sin(time / 180) * 4 : 24;

    this.ctx.globalAlpha = this.exit.active ? 0.9 : 0.35;
    this.ctx.fillStyle = this.exit.active ? '#ffe59b' : '#c7c7bc';
    this.ctx.shadowBlur = this.exit.active ? 24 : 8;
    this.ctx.shadowColor = '#ffe59b';
    this.ctx.beginPath();
    this.ctx.arc(0, 0, radius, 0, Math.PI * 2);
    this.ctx.fill();
    this.ctx.restore();
  }

  private drawPlayer(time: number) {
    if (this.player.state === 'move') {
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

    if (!this.tip) {
      return;
    }

    this.tip.textContent = message;

    window.setTimeout(() => {
      if (performance.now() > this.messageUntil && this.tip) {
        this.tip.textContent = GAME_DEFAULT_TIP;
      }
    }, 2300);
  }
}
