import type { SaveData } from '../types';
import { drawMushroomBuddy } from '../game/mushroomBuddy';
import { menuVignettePose } from './menuVignetteMotion';

type Settings = SaveData['settings'];
const FILES: Record<string, string> = Object.fromEntries([
  ...['idle-front', 'idle-side', 'crouch-lower', 'crouch', 'crouch-happy', 'turn-quarter'].map(key => [key, `menu-walk-redrawn/${key}.png`]),
  ...Array.from({ length: 8 }, (_, i) => [`step-${i + 1}`, `menu-walk-redrawn/step-${i + 1}.png`]),
  ['light', 'menu-fx-redrawn/orb.png'],
  ['firefly', 'menu-fx-redrawn/firefly.png'],
]);

/** Decorative scene: owns its clock and releases all work when the menu is replaced. */
export class MenuVignette {
  private context: CanvasRenderingContext2D;
  private images = new Map<string, HTMLImageElement>();
  private media = matchMedia('(prefers-reduced-motion: reduce)');
  private observer: ResizeObserver;
  private frame = 0;
  private elapsed = 0;
  private previous = 0;
  private paused = document.hidden;
  private destroyed = false;
  private ready = false;

  constructor(private canvas: HTMLCanvasElement, private settings: Settings) {
    this.context = canvas.getContext('2d')!;
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(canvas);
    this.observer.observe(canvas.closest('.journey-menu')!);
    this.media.addEventListener('change', this.refresh);
    const loads = Object.entries(FILES).map(([key, file]) => new Promise<void>(resolve => {
      const img = new Image();
      img.onload = img.onerror = () => resolve();
      img.src = `./images/${file}`;
      this.images.set(key, img);
    }));
    void Promise.all(loads).then(() => {
      if (this.destroyed) return;
      this.ready = Boolean(this.images.get('idle-front')?.naturalWidth);
      this.canvas.parentElement?.classList.toggle('is-ready', this.ready);
      this.refresh();
    });
    this.resize();
  }

  private get lowMotion() { return this.settings.lowMotion || this.media.matches; }
  configure(settings: Settings) { this.settings = settings; this.resize(); this.refresh(); }
  pause(value: boolean) { this.paused = value; this.refresh(); }
  private resize = () => {
    const screen = this.canvas.closest<HTMLElement>('.journey-menu')!;
    screen.style.setProperty('--landscape-scale', String(Math.max(screen.clientWidth / 1280, screen.clientHeight / 720)));
    const ratio = this.settings.quality === 'soft' ? 1 : Math.min(devicePixelRatio || 1, 2);
    const scale = Math.max(.5, this.canvas.getBoundingClientRect().width / 1280) * ratio;
    this.canvas.width = Math.round(1280 * scale);
    this.canvas.height = Math.round(720 * scale);
    this.draw();
  };
  private refresh = () => {
    cancelAnimationFrame(this.frame); this.frame = 0; this.previous = 0;
    this.draw();
    if (!this.paused && !this.lowMotion && this.ready && !this.destroyed) this.frame = requestAnimationFrame(this.tick);
  };
  private tick = (now: number) => {
    if (this.destroyed) return;
    if (this.previous) this.elapsed += Math.min(64, now - this.previous);
    this.previous = now;
    this.draw();
    this.frame = requestAnimationFrame(this.tick);
  };

  private draw() {
    const c = this.context;
    c.setTransform(this.canvas.width / 1280, 0, 0, this.canvas.height / 720, 0, 0);
    c.clearRect(0, 0, 1280, 720);
    if (!this.ready) return;
    const pose = menuVignettePose(this.elapsed, this.lowMotion), { hero, buddy, light } = pose;
    const size = 290 - hero.progress * 16;
    if (this.settings.particles) this.drawFireflies(pose.time, false);

    // Warm reflected light and tight contact shadows keep the feet on the stone.
    if (this.settings.dynamicLight) {
      c.save(); c.translate(light.x, hero.y + 2); c.scale(1, .26);
      const glow = c.createRadialGradient(0, 0, 0, 0, 0, 66);
      glow.addColorStop(0, '#ffdc7b45'); glow.addColorStop(1, '#ffdc7b00');
      c.fillStyle = glow; c.fillRect(-66, -66, 132, 132); c.restore();
    }
    c.save(); c.translate(hero.x, hero.y + 2); c.scale(1, .26);
    const shadow = c.createRadialGradient(0, 0, 4, 0, 0, 43);
    shadow.addColorStop(0, '#4b482b65'); shadow.addColorStop(.6, '#4b482b30'); shadow.addColorStop(1, '#4b482b00');
    c.fillStyle = shadow; c.fillRect(-43, -43, 86, 86); c.restore();

    const img = this.images.get(hero.key)?.naturalWidth ? this.images.get(hero.key)! : this.images.get('idle-front')!;
    const breath = this.lowMotion || hero.walking ? 0 : Math.sin(pose.time / 900) * .004;
    c.save(); c.translate(hero.x, hero.y); c.scale(hero.flip ? -1 : 1, 1 + breath);
    c.drawImage(img, -size / 2, -size * 236 / 256, size, size); c.restore();
    drawMushroomBuddy(c, buddy.x, buddy.y, 53, pose.time, {
      moving: buddy.walking, happy: buddy.happy, lowMotion: this.lowMotion,
    });
    if (this.settings.particles) this.drawFireflies(pose.time, true);

    // The light leads the walk, waits near her hands, then doubles back.
    if (this.settings.particles && !this.lowMotion) {
      for (let i = 1; i <= 7; i++) {
        const past = menuVignettePose(Math.max(0, this.elapsed - i * 95)).light;
        c.beginPath(); c.arc(past.x, past.y, 2.1 - i * .18, 0, Math.PI * 2);
        c.fillStyle = `rgba(222,168,65,${.32 * (1 - i / 8)})`; c.fill();
      }
    }
    const radius = this.settings.dynamicLight ? 32 + (this.lowMotion ? 0 : Math.sin(pose.time / 430) * 3) : 16;
    const halo = c.createRadialGradient(light.x, light.y, 1, light.x, light.y, radius);
    halo.addColorStop(0, '#fffbe9f0'); halo.addColorStop(.18, '#ffe8a6b0'); halo.addColorStop(.55, '#ffce6f45'); halo.addColorStop(1, '#ffcf7000');
    c.fillStyle = halo; c.fillRect(light.x - radius, light.y - radius, radius * 2, radius * 2);
    const lightImage = this.images.get('light');
    if (lightImage?.naturalWidth) {
      // Keep the supplied round orb and its tiny sparkles at their original aspect ratio.
      const width = 86, height = width * lightImage.naturalHeight / lightImage.naturalWidth;
      c.drawImage(lightImage, light.x - width / 2, light.y - height / 2, width, height);
    } else {
      c.fillStyle = '#fff6cc'; c.beginPath(); c.arc(light.x, light.y, 6, 0, Math.PI * 2); c.fill();
    }
  }

  private drawFireflies(time: number, foreground: boolean) {
    const sprite = this.images.get('firefly');
    if (!sprite?.naturalWidth) return;
    const c = this.context, t = this.lowMotion ? 0 : time / 24000 * Math.PI * 2;
    const insects = foreground ? [[185, 562, 72, 30, 18, 1.8]]
      : [[580, 348, 46, 39, 19, .3], [145, 408, 42, 25, 16, 2.4], [649, 491, 56, 26, 22, 4.1]];
    for (const [x, y, width, rx, ry, phase] of insects) {
      const angle = t + phase;
      c.save();
      c.translate(x + Math.sin(angle) * rx, y + Math.sin(angle * 2) * ry);
      c.rotate(this.lowMotion ? 0 : Math.cos(angle) * .13);
      c.globalAlpha = foreground ? .92 : .72;
      const height = width * sprite.naturalHeight / sprite.naturalWidth;
      c.drawImage(sprite, -width / 2, -height / 2, width, height);
      c.restore();
    }
  }

  destroy() {
    this.destroyed = true;
    cancelAnimationFrame(this.frame);
    this.observer.disconnect();
    this.media.removeEventListener('change', this.refresh);
  }
}
